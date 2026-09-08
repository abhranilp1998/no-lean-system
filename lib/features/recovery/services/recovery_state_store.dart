import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

abstract interface class RecoveryStateStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> preserve(String value);
  Future<List<String>> recoveryCopies();
  Future<void> removeLegacyPin();
}

/// Compatibility adapter, also used by tests. Production uses the file store.
class PreferencesRecoveryStateStore implements RecoveryStateStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read() async => (await _prefs).getString('recovery_state');

  Future<void> _put(String key, String value) async {
    if (!await (await _prefs).setString(key, value)) {
      throw const FileSystemException('Recovery data could not be saved.');
    }
  }

  @override
  Future<void> write(String value) => _put('recovery_state', value);

  @override
  Future<void> preserve(String value) => _put(
    'recovery_snapshot_${const Uuid().v5(Namespace.url.value, value)}',
    value,
  );

  @override
  Future<List<String>> recoveryCopies() async {
    final prefs = await _prefs;
    return [
      for (final key in prefs.getKeys())
        if (key.startsWith('recovery_snapshot_') ||
            key == 'recovery_state_v5_backup' ||
            key == 'recovery_state_rejected_backup')
          if (prefs.get(key) case final String value) value,
    ];
  }

  @override
  Future<void> removeLegacyPin() async {
    final prefs = await _prefs;
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('recovery_'),
    )) {
      final value = prefs.get(key);
      if (value is! String) continue;
      Map<String, dynamic> map;
      try {
        map = Map<String, dynamic>.from(jsonDecode(value) as Map);
      } catch (_) {
        continue;
      }
      if (map.containsKey('pin')) {
        map.remove('pin');
        await _put(key, jsonEncode(map));
      }
    }
  }
}

/// A flushed temporary file is atomically renamed into place. The previous
/// committed file and migration sources are retained. Reads never silently
/// replace a damaged/newer current file with an older copy.
class FileRecoveryStateStore implements RecoveryStateStore {
  FileRecoveryStateStore({Directory? directory, RecoveryStateStore? legacy})
    : _directory = directory,
      _legacy = legacy ?? PreferencesRecoveryStateStore();

  Directory? _directory;
  final RecoveryStateStore _legacy;

  Future<Directory> get _root async {
    final directory = _directory ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/recovery',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _file(String name) async => File('${(await _root).path}/$name');

  @override
  Future<String?> read() async {
    final current = await _file('current.json');
    return await current.exists() ? current.readAsString() : _legacy.read();
  }

  Future<void> _replace(File target, String value) async {
    final temporary = File('${target.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsString(value, flush: true);
      if (await temporary.readAsString() != value) {
        throw const FileSystemException('Recovery write verification failed.');
      }
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {
          /* Inert staging file. */
        }
      }
    }
  }

  @override
  Future<void> write(String value) async {
    final current = await _file('current.json');
    if (await current.exists()) {
      await _replace(
        await _file('previous.json'),
        await current.readAsString(),
      );
    }
    await _replace(current, value);
  }

  @override
  Future<void> preserve(String value) async {
    final id = const Uuid().v5(Namespace.url.value, value);
    final target = await _file('preserved-$id.json');
    if (!await target.exists()) await _replace(target, value);
  }

  @override
  Future<List<String>> recoveryCopies() async {
    final copies = <String>[];
    final previous = await _file('previous.json');
    if (await previous.exists()) copies.add(await previous.readAsString());
    await for (final file in (await _root).list()) {
      if (file is File &&
          file.path.contains('preserved-') &&
          file.path.endsWith('.json')) {
        copies.add(await file.readAsString());
      }
    }
    copies.addAll(await _legacy.recoveryCopies());
    return copies.toSet().toList();
  }

  @override
  Future<void> removeLegacyPin() => _legacy.removeLegacyPin();
}
