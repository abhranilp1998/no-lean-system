import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/note_crypto.dart';

abstract interface class NoteKeyStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// The phone's secure storage (Android Keystore backed), in its own
/// namespace, next to the PIN hash.
class SecureNoteKeyStorage implements NoteKeyStorage {
  SecureNoteKeyStorage([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'no_lean_notes'),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// No secure storage: nothing can be stored, so notes stay plain. Used when the
/// app runs with a substitute PIN gateway (tests), never on a real phone.
class UnavailableNoteKeyStorage implements NoteKeyStorage {
  const UnavailableNoteKeyStorage();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Secure storage unavailable.');

  @override
  Future<void> delete(String key) async {}
}

/// This phone's note key and the PIN-wrapped copy of it.
class LocalNoteKey {
  const LocalNoteKey({
    required this.keyId,
    required this.key,
    required this.wrap,
  });

  final String keyId;
  final Uint8List key;
  final NoteKeyWrap? wrap;
}

/// Keeps the note key. Every method fails safe: when secure storage cannot be
/// read or written the vault reports "no key" and notes stay as they are,
/// never half-encrypted.
class NoteVault {
  NoteVault({NoteKeyStorage? storage, this.rounds = defaultNotePbkdf2Rounds})
    : _storage = storage ?? SecureNoteKeyStorage();

  final NoteKeyStorage _storage;
  final int rounds;

  static const _slot = 'note_key_v1';

  /// Keys unlocked from a PIN this session (a backup's, or after a restore).
  final Map<String, Uint8List> _session = {};

  Future<LocalNoteKey?> localKey() async {
    try {
      final raw = await _storage.read(_slot);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final key = tryB64(json['key']);
      final kid = json['kid'];
      if (key == null || key.length != noteKeyBytes || kid is! String) {
        return null;
      }
      return LocalNoteKey(
        keyId: kid,
        key: key,
        wrap: NoteKeyWrap.tryFromJson(json['w']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _store(LocalNoteKey k) async {
    try {
      await _storage.write(
        _slot,
        jsonEncode({
          'kid': k.keyId,
          'key': b64(k.key),
          if (k.wrap != null) 'w': k.wrap!.toJson(),
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Turns encryption on for [pin]: keeps this phone's key (or makes one) and
  /// wraps it under the PIN. Returns null, changing nothing, if the key could
  /// not be stored. Calling it again with a new PIN re-wraps the same key, so
  /// changing the PIN never re-encrypts or loses a note.
  Future<LocalNoteKey?> enable(String pin) async {
    final existing = await localKey();
    final key = existing?.key ?? randomBytes(noteKeyBytes);
    final kid = existing?.keyId ?? b64(randomBytes(9));
    if (existing == null) {
      // Store the bare key first: if secure storage is unusable we stop
      // here, before spending time on the PIN derivation.
      final bare = LocalNoteKey(keyId: kid, key: key, wrap: null);
      if (!await _store(bare)) return null;
    }
    final wrap = await wrapNoteKey(key, pin, rounds: rounds);
    final next = LocalNoteKey(keyId: kid, key: key, wrap: wrap);
    if (await _store(next)) return next;
    return existing;
  }

  /// Adopts a key rebuilt from a PIN as this phone's key (secure storage was
  /// lost, or the app was restored on a new phone).
  Future<LocalNoteKey?> adopt({
    required String keyId,
    required Uint8List key,
    required NoteKeyWrap? wrap,
  }) async {
    final next = LocalNoteKey(keyId: keyId, key: key, wrap: wrap);
    return await _store(next) ? next : null;
  }

  /// Turns encryption off. Only call once every note is readable again.
  Future<void> disable() async {
    try {
      await _storage.delete(_slot);
    } catch (_) {
      /* Nothing to remove if it could not be read either. */
    }
    _session.clear();
  }

  void remember(String keyId, Uint8List key) => _session[keyId] = key;

  void forgetSession() => _session.clear();

  /// The key for [keyId]: this phone's, else one unlocked this session.
  Future<Uint8List?> keyFor(String keyId) async {
    final local = await localKey();
    if (local != null && local.keyId == keyId) return local.key;
    return _session[keyId];
  }
}
