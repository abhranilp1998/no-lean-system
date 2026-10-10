import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/zone_entry.dart';

/// Hand-off from the background geofence isolate to the app. The isolate
/// never writes the recovery state (it could race the app's writes); it
/// appends one JSON line here and the app imports the lines on next load or
/// resume, honouring the zone-history setting at that moment.
abstract interface class ZoneEntryInbox {
  Future<void> append(ZoneEntry entry);

  /// Returns every pending entry. They stay pending until [acknowledge].
  Future<List<ZoneEntry>> drain();

  /// Removes the entries returned by the last [drain], after they are saved.
  Future<void> acknowledge();
}

class NoopZoneEntryInbox implements ZoneEntryInbox {
  const NoopZoneEntryInbox();

  @override
  Future<void> append(ZoneEntry entry) async {}

  @override
  Future<List<ZoneEntry>> drain() async => const [];

  @override
  Future<void> acknowledge() async {}
}

class FileZoneEntryInbox implements ZoneEntryInbox {
  FileZoneEntryInbox({Directory? directory}) : _directory = directory;

  Directory? _directory;

  Future<File> _file(String name) async {
    final directory = _directory ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/recovery',
    );
    await directory.create(recursive: true);
    return File('${directory.path}/$name');
  }

  @override
  Future<void> append(ZoneEntry entry) async {
    final file = await _file('zone_entries.jsonl');
    await file.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<List<ZoneEntry>> drain() async {
    final inbox = await _file('zone_entries.jsonl');
    final draining = await _file('zone_entries.draining');
    // Rename first so a concurrent append starts a fresh inbox file.
    if (await inbox.exists() && !await draining.exists()) {
      await inbox.rename(draining.path);
    }
    if (!await draining.exists()) return const [];
    final entries = <ZoneEntry>[];
    for (final line in await draining.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final entry = ZoneEntry.tryDecode(jsonDecode(line));
        if (entry != null) entries.add(entry);
      } catch (_) {
        /* A torn line from a killed isolate is skipped. */
      }
    }
    return entries;
  }

  @override
  Future<void> acknowledge() async {
    final draining = await _file('zone_entries.draining');
    if (await draining.exists()) await draining.delete();
  }
}
