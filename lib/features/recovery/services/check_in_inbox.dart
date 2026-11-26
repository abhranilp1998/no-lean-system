import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/daily_check_in.dart';

/// Hand-off from the background notification isolate to the app, the same
/// pattern as the zone-entry inbox: the isolate never writes the recovery
/// state (it could race the app). It appends one JSON line here and the app
/// turns the lines into events on next load or resume, using the tap time.
abstract interface class CheckInInbox {
  Future<void> append(CheckInEntry entry);

  /// Every pending entry. They stay pending until [acknowledge].
  Future<List<CheckInEntry>> drain();

  /// Removes the entries returned by the last [drain], after they are saved.
  Future<void> acknowledge();
}

class NoopCheckInInbox implements CheckInInbox {
  const NoopCheckInInbox();

  @override
  Future<void> append(CheckInEntry entry) async {}

  @override
  Future<List<CheckInEntry>> drain() async => const [];

  @override
  Future<void> acknowledge() async {}
}

class FileCheckInInbox implements CheckInInbox {
  FileCheckInInbox({Directory? directory}) : _directory = directory;

  Directory? _directory;

  Future<File> _file(String name) async {
    final directory = _directory ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/recovery',
    );
    await directory.create(recursive: true);
    return File('${directory.path}/$name');
  }

  @override
  Future<void> append(CheckInEntry entry) async {
    final file = await _file('check_in_answers.jsonl');
    await file.writeAsString(
      '${entry.encode()}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<List<CheckInEntry>> drain() async {
    final inbox = await _file('check_in_answers.jsonl');
    final draining = await _file('check_in_answers.draining');
    // Rename first so a concurrent append starts a fresh inbox file.
    if (await inbox.exists() && !await draining.exists()) {
      await inbox.rename(draining.path);
    }
    if (!await draining.exists()) return const [];
    final entries = <CheckInEntry>[];
    for (final line in await draining.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final entry = CheckInEntry.tryDecode(jsonDecode(line));
        if (entry != null) entries.add(entry);
      } catch (_) {
        /* A torn line from a killed isolate is skipped. */
      }
    }
    return entries;
  }

  @override
  Future<void> acknowledge() async {
    final draining = await _file('check_in_answers.draining');
    if (await draining.exists()) await draining.delete();
  }
}
