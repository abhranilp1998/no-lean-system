import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/zones/domain/background_zone_alert.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/domain/zone_entry.dart';
import 'package:no_lean/features/zones/services/zone_entry_inbox.dart';

import '../../../support/recovery_fakes.dart';

class MemoryInbox implements ZoneEntryInbox {
  final pending = <ZoneEntry>[];
  int acknowledged = 0;
  List<ZoneEntry> _drained = const [];

  @override
  Future<void> append(ZoneEntry entry) async => pending.add(entry);

  @override
  Future<List<ZoneEntry>> drain() async => _drained = List.of(pending);

  @override
  Future<void> acknowledge() async {
    pending.removeWhere(_drained.contains);
    acknowledged++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final at = DateTime(2026, 10, 9, 21, 30);

  Future<(RecoveryController, MemoryRecoveryStore, MemoryInbox)> loaded({
    String? stored,
  }) async {
    final store = MemoryRecoveryStore(stored);
    final inbox = MemoryInbox();
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      zoneInbox: inbox,
    );
    await controller.load();
    return (controller, store, inbox);
  }

  Iterable<RecoveryEvent> entries(RecoveryController c) =>
      c.events.where((e) => e.type == RecoveryEventType.zoneEntry);

  Future<DangerZone> addZone(RecoveryController c) =>
      c.addZone(name: 'Old bar', latitude: 22.5726, longitude: 88.3639);

  test('off by default: v10 states migrate with history off', () async {
    final (controller, store, _) = await loaded(
      stored: jsonEncode({'stateVersion': 10, 'events': [], 'zones': []}),
    );
    expect(controller.zoneHistory, isFalse);
    final saved = jsonDecode(store.value!) as Map;
    expect(saved['stateVersion'], RecoveryController.stateVersion);
    expect(saved['zoneHistory'], isFalse);
  });

  test('entries are not recorded while history is off', () async {
    final (controller, _, _) = await loaded();
    final zone = await addZone(controller);
    expect(
      await controller.recordZoneEntry(ZoneEntry.of(zone, at, 'app')),
      isFalse,
    );
    expect(entries(controller), isEmpty);
  });

  test('with history on, entries store name and time but no coordinates, '
      'and a second report of the same visit is merged', () async {
    final (controller, store, _) = await loaded();
    final zone = await addZone(controller);
    await controller.setZoneHistory(true);
    expect(
      await controller.recordZoneEntry(ZoneEntry.of(zone, at, 'app')),
      isTrue,
    );
    expect(
      await controller.recordZoneEntry(
        ZoneEntry.of(zone, at.add(const Duration(minutes: 5)), 'background'),
      ),
      isFalse,
    );
    expect(
      await controller.recordZoneEntry(
        ZoneEntry.of(zone, at.add(const Duration(hours: 2)), 'app'),
      ),
      isTrue,
    );
    final first = entries(controller).first;
    expect(first.timestamp, at);
    expect(first.metadata, {
      'zoneId': zone.id,
      'zoneName': 'Old bar',
      'source': 'app',
    });
    final persisted = jsonEncode((jsonDecode(store.value!) as Map)['events']);
    expect(persisted, isNot(contains('88.36')));
    expect(persisted, isNot(contains('22.57')));
  });

  test('location keys are stripped even from crafted events', () {
    final event = RecoveryEvent.create(
      type: RecoveryEventType.zoneEntry,
      metadata: {
        'zoneId': 'z',
        'zoneName': 'X',
        'latitude': 1.0,
        'lng': 2.0,
        'accuracyMeters': 5,
      },
    );
    expect(event.metadata.keys, unorderedEquals(['zoneId', 'zoneName']));
    expect(
      () => RecoveryEvent.create(
        type: RecoveryEventType.zoneEntry,
        metadata: {'zoneId': 'z'},
      ),
      throwsFormatException,
    );
  });

  test('clearing removes every entry and nothing else', () async {
    final (controller, _, _) = await loaded();
    final zone = await addZone(controller);
    await controller.setZoneHistory(true);
    await controller.recordZoneEntry(ZoneEntry.of(zone, at, 'app'));
    await controller.recordZoneEntry(
      ZoneEntry.of(zone, at.add(const Duration(days: 1)), 'app'),
    );
    final others = controller.events.length - 2;
    expect(await controller.clearZoneHistory(), 2);
    expect(entries(controller), isEmpty);
    expect(controller.events.length, others);
    expect(controller.zones, hasLength(1));
  });

  test('background inbox entries import only with history on', () async {
    final (controller, _, inbox) = await loaded();
    final zone = await addZone(controller);
    inbox.pending.add(ZoneEntry.of(zone, at, 'background'));
    expect(await controller.importZoneInbox(), 0);
    expect(inbox.pending, isEmpty, reason: 'discarded, not kept for later');
    expect(entries(controller), isEmpty);

    await controller.setZoneHistory(true);
    inbox.pending.add(ZoneEntry.of(zone, at, 'background'));
    expect(await controller.importZoneInbox(), 1);
    expect(entries(controller).single.metadata['source'], 'background');
  });

  test('imports never switch zone history on', () async {
    final (controller, _, _) = await loaded();
    await controller.mergeImportedEvents(
      const [],
      preferences: {'zoneHistory': true},
      restorePreferences: true,
    );
    expect(controller.zoneHistory, isFalse);
  });

  test('backups carry zone entries (format 6+)', () async {
    final (controller, _, _) = await loaded();
    final zone = await addZone(controller);
    await controller.setZoneHistory(true);
    await controller.recordZoneEntry(ZoneEntry.of(zone, at, 'app'));
    final service = BackupService();
    final payload = service.buildBackupPayload(
      controller.events,
      preferences: controller.portablePreferences,
      zones: controller.zones,
    );
    expect(payload['version'], BackupService.currentBackupVersion);
    final preview = service.validateBackupJson(jsonEncode(payload));
    expect(
      preview.events.where((e) => e.type == RecoveryEventType.zoneEntry),
      hasLength(1),
    );
  });

  group('background isolate', () {
    final zone = DangerZone(
      id: 'abc',
      name: 'Old bar',
      latitude: 22.5,
      longitude: 88.3,
      radiusMeters: 200,
      createdAt: DateTime(2026, 10, 1),
    );
    String state({required bool history, bool background = true}) =>
        jsonEncode({
          'zoneHistory': history,
          'backgroundGeofencing': background,
          'zones': [zone.toJson()],
        });

    test('hands entries over only when history and background are on', () {
      final ids = ['${zoneGeofencePrefix}abc'];
      expect(
        backgroundZoneEntries(
          rawState: state(history: false),
          geofenceIds: ids,
          now: at,
        ),
        isEmpty,
      );
      expect(
        backgroundZoneEntries(
          rawState: state(history: true, background: false),
          geofenceIds: ids,
          now: at,
        ),
        isEmpty,
      );
      final handed = backgroundZoneEntries(
        rawState: state(history: true),
        geofenceIds: ids,
        now: at,
      );
      expect(handed.single.zoneName, 'Old bar');
      expect(handed.single.toJson().keys, isNot(contains('latitude')));
      expect(
        backgroundZoneEntries(rawState: '{bad', geofenceIds: ids, now: at),
        isEmpty,
      );
    });

    test('the file inbox survives torn lines and drains once', () async {
      final dir = await Directory.systemTemp.createTemp('inbox');
      addTearDown(() => dir.delete(recursive: true));
      final inbox = FileZoneEntryInbox(directory: dir);
      await inbox.append(ZoneEntry.of(zone, at, 'background'));
      await File(
        '${dir.path}/zone_entries.jsonl',
      ).writeAsString('{"zoneId":"abc","zon', mode: FileMode.append);
      final drained = await inbox.drain();
      expect(drained.single.zoneName, 'Old bar');
      // New appends during a drain go to a fresh inbox file.
      await inbox.append(
        ZoneEntry.of(zone, at.add(const Duration(hours: 1)), 'background'),
      );
      await inbox.acknowledge();
      final next = await inbox.drain();
      expect(next.single.at, at.add(const Duration(hours: 1)));
      await inbox.acknowledge();
      expect(await inbox.drain(), isEmpty);
    });
  });
}
