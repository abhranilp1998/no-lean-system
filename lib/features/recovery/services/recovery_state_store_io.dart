import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'recovery_state_store.dart';

RecoveryStateStore createRecoveryStateStore() => FileRecoveryStateStore();

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
