import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where voice recordings live: files on this phone, never in app state and
/// never in backups. A note's id names its file (`<id>.m4a` when plain,
/// `<id>.nlv` when encrypted).
abstract interface class VoiceNoteStore {
  Future<Uint8List?> read(String id, {required bool encrypted});

  Future<void> write(String id, Uint8List bytes, {required bool encrypted});

  Future<void> delete(String id, {required bool encrypted});

  Future<bool> exists(String id, {required bool encrypted});
}

class FileVoiceNoteStore implements VoiceNoteStore {
  FileVoiceNoteStore([Future<Directory> Function()? root])
    : _root = root ?? _defaultRoot;

  final Future<Directory> Function() _root;

  static Future<Directory> _defaultRoot() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/future_notes');
  }

  Future<File> _file(String id, bool encrypted) async {
    final dir = await _root();
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$safe.${encrypted ? 'nlv' : 'm4a'}');
  }

  @override
  Future<Uint8List?> read(String id, {required bool encrypted}) async {
    try {
      final file = await _file(id, encrypted);
      return await file.exists() ? await file.readAsBytes() : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Written to a temporary name and renamed, so a crash never leaves half a
  /// recording under the real name.
  @override
  Future<void> write(
    String id,
    Uint8List bytes, {
    required bool encrypted,
  }) async {
    final file = await _file(id, encrypted);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> delete(String id, {required bool encrypted}) async {
    try {
      final file = await _file(id, encrypted);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      /* Already gone, or unreadable: nothing more to remove. */
    }
  }

  @override
  Future<bool> exists(String id, {required bool encrypted}) async {
    try {
      return await (await _file(id, encrypted)).exists();
    } on FileSystemException {
      return false;
    }
  }
}

class MemoryVoiceNoteStore implements VoiceNoteStore {
  final Map<String, Uint8List> files = {};

  String _name(String id, bool encrypted) => '$id.${encrypted ? 'nlv' : 'm4a'}';

  @override
  Future<Uint8List?> read(String id, {required bool encrypted}) async =>
      files[_name(id, encrypted)];

  @override
  Future<void> write(
    String id,
    Uint8List bytes, {
    required bool encrypted,
  }) async {
    files[_name(id, encrypted)] = bytes;
  }

  @override
  Future<void> delete(String id, {required bool encrypted}) async {
    files.remove(_name(id, encrypted));
  }

  @override
  Future<bool> exists(String id, {required bool encrypted}) async =>
      files.containsKey(_name(id, encrypted));
}
