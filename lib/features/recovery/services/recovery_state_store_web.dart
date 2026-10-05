import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import 'recovery_state_store.dart';

RecoveryStateStore createRecoveryStateStore() => BrowserRecoveryStateStore();

/// Keeps the current and previous history in one IndexedDB transaction. A
/// rejected read or write never falls back to a fresh, writable history.
class BrowserRecoveryStateStore implements RecoveryStateStore {
  BrowserRecoveryStateStore({
    this.databaseName = 'no_lean_recovery',
    RecoveryStateStore? legacy,
  }) : _legacy = legacy ?? PreferencesRecoveryStateStore();

  final String databaseName;
  final RecoveryStateStore _legacy;
  static const _records = 'history';
  String? _expectedCurrent;

  Future<web.IDBDatabase> _open() {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_records);
    }).toJS;
    request.onsuccess = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      if (completer.isCompleted) {
        database.close();
      } else {
        completer.complete(database);
      }
    }).toJS;
    void fail(web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Browser recovery storage could not be opened.'),
        );
      }
    }

    request.onerror = fail.toJS;
    request.onblocked = fail.toJS;
    return completer.future;
  }

  Future<T> _transaction<T>(
    String mode,
    void Function(web.IDBObjectStore, void Function(T Function())) operation,
  ) async {
    final database = await _open();
    try {
      final transaction = mode == 'readwrite'
          ? database.transaction(
              _records.toJS,
              mode,
              web.IDBTransactionOptions(durability: 'strict'),
            )
          : database.transaction(_records.toJS, mode);
      final completer = Completer<T>();
      T? result;
      Object? failure;
      StackTrace? failureStack;
      transaction.oncomplete = ((web.Event _) {
        completer.complete(result as T);
      }).toJS;
      transaction.onabort = ((web.Event _) {
        completer.completeError(
          failure ?? StateError('Browser recovery transaction failed.'),
          failureStack,
        );
      }).toJS;

      void capture(T Function() readResult) {
        try {
          result = readResult();
        } catch (error, stack) {
          failure = error;
          failureStack = stack;
          transaction.abort();
        }
      }

      try {
        operation(transaction.objectStore(_records), capture);
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
        transaction.abort();
      }
      // Request success alone is insufficient: acknowledge only the commit.
      return await completer.future;
    } finally {
      database.close();
    }
  }

  String? _string(JSAny? value) {
    if (value == null) return null;
    if (!value.isA<JSString>()) {
      throw const FormatException('Browser recovery record is not text.');
    }
    return (value as JSString).toDart;
  }

  @override
  Future<String?> read() async {
    final current = await _transaction<String?>('readonly', (store, capture) {
      final request = store.get('current'.toJS);
      request.onsuccess = ((web.Event _) {
        capture(() => _string(request.result));
      }).toJS;
    });
    _expectedCurrent = current;
    return current ?? await _legacy.read();
  }

  @override
  Future<void> write(String value) async {
    await _transaction<void>('readwrite', (store, capture) {
      final request = store.get('current'.toJS);
      request.onsuccess = ((web.Event _) {
        capture(() {
          final previous = _string(request.result);
          if (previous != _expectedCurrent) {
            throw StateError(
              'Recovery history changed in another tab. Reload before saving.',
            );
          }
          if (previous != null) store.put(previous.toJS, 'previous'.toJS);
          store.put(value.toJS, 'current'.toJS);
        });
      }).toJS;
    });
    _expectedCurrent = value;
  }

  @override
  Future<void> preserve(String value) async {
    final id = const Uuid().v5(Namespace.url.value, value);
    await _transaction<void>('readwrite', (store, capture) {
      store.put(value.toJS, 'preserved-$id'.toJS);
      capture(() {});
    });
  }

  void _readRecords(
    web.IDBObjectStore store,
    void Function(Map<String, String> Function()) capture,
  ) {
    final keys = store.getAllKeys();
    final values = store.getAll();
    values.onsuccess = ((web.Event _) {
      capture(() {
        final names = (keys.result as JSArray<JSAny?>).toDart;
        final records = (values.result as JSArray<JSAny?>).toDart;
        return {
          for (var index = 0; index < names.length; index++)
            _string(names[index])!: _string(records[index])!,
        };
      });
    }).toJS;
  }

  @override
  Future<List<String>> recoveryCopies() async {
    final records = await _transaction<Map<String, String>>(
      'readonly',
      _readRecords,
    );
    return {
      for (final entry in records.entries)
        if (entry.key != 'current') entry.value,
      ...await _legacy.recoveryCopies(),
    }.toList();
  }

  String _withoutLegacyPin(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map && decoded.containsKey('pin')) {
        decoded.remove('pin');
        return jsonEncode(decoded);
      }
    } on FormatException {
      // Unreadable originals remain intact for recovery.
    }
    return value;
  }

  @override
  Future<void> removeLegacyPin() async {
    await _legacy.removeLegacyPin();
    await _transaction<Map<String, String>>('readwrite', (store, capture) {
      _readRecords(store, (readRecords) {
        capture(() {
          final records = readRecords();
          for (final entry in records.entries) {
            final sanitized = _withoutLegacyPin(entry.value);
            if (sanitized != entry.value) {
              store.put(sanitized.toJS, entry.key.toJS);
            }
          }
          return records;
        });
      });
    });
    if (_expectedCurrent != null) {
      _expectedCurrent = _withoutLegacyPin(_expectedCurrent!);
    }
  }
}
