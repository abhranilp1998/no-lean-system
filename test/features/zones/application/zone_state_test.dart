import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/services/geofence_gateway.dart';

import '../../../support/recovery_fakes.dart';

class FakeGeofences implements GeofenceGateway {
  final synced = <List<String>>[];
  int clears = 0;

  @override
  Future<void> clear() async => clears++;

  @override
  Future<void> sync(List<DangerZone> zones) async =>
      synced.add(zones.map((z) => z.name).toList());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(RecoveryController, MemoryRecoveryStore, FakeGeofences)> loaded({
    String? stored,
  }) async {
    final store = MemoryRecoveryStore(stored);
    final geofences = FakeGeofences();
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      geofences: geofences,
    );
    await controller.load();
    return (controller, store, geofences);
  }

  test('v8 state migrates to v9 with no zones and monitoring off', () async {
    final v8 = jsonEncode({
      'stateVersion': 8,
      'events': [
        RecoveryEvent.create(
          type: RecoveryEventType.recoveryStart,
          timestamp: DateTime(2026, 9, 1),
        ).toJson(),
      ],
    });
    final (controller, store, _) = await loaded(stored: v8);
    expect(controller.zones, isEmpty);
    expect(controller.zoneMonitoring, isFalse);
    expect(controller.backgroundGeofencing, isFalse);
    final saved = jsonDecode(store.value!) as Map;
    expect(saved['stateVersion'], 9);
    expect(saved['zones'], isEmpty);
    expect(store.copies.single, contains('"stateVersion":8'));
  });

  test('zones persist and reload', () async {
    final (controller, store, _) = await loaded();
    await controller.addZone(
      name: ' Corner shop ',
      latitude: 22.57,
      longitude: 88.36,
      radiusMeters: 250,
    );
    final reloaded = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
    );
    await reloaded.load();
    expect(reloaded.zones.single.name, 'Corner shop');
    expect(reloaded.zones.single.radiusMeters, 250);
  });

  test('invalid zones are rejected without changing state', () async {
    final (controller, _, _) = await loaded();
    await expectLater(
      controller.addZone(name: 'x', latitude: 95, longitude: 0),
      throwsFormatException,
    );
    expect(controller.zones, isEmpty);
  });

  test(
    'deleting or shrinking a zone authenticates when a PIN exists',
    () async {
      final (controller, _, _) = await loaded();
      final zone = await controller.addZone(
        name: 'Bar',
        latitude: 22.5,
        longitude: 88.3,
        radiusMeters: 300,
      );
      await controller.enableRelapseLock('2468');

      expect(
        await controller.updateZone(
          zone.id,
          radiusMeters: 400,
          tryBiometrics: false,
        ),
        ProtectedActionResult.completed,
      );
      expect(
        await controller.updateZone(
          zone.id,
          radiusMeters: 150,
          tryBiometrics: false,
        ),
        ProtectedActionResult.authenticationRequired,
      );
      expect(controller.zones.single.radiusMeters, 400);
      expect(
        await controller.deleteZone(zone.id, tryBiometrics: false),
        ProtectedActionResult.authenticationRequired,
      );
      expect(
        await controller.deleteZone(zone.id, pin: '2468', tryBiometrics: false),
        ProtectedActionResult.completed,
      );
      expect(controller.zones, isEmpty);
    },
  );

  test('turning location monitoring off never needs authentication', () async {
    final (controller, _, _) = await loaded();
    await controller.enableRelapseLock('2468');
    await controller.setZoneMonitoring(true);
    await controller.setBackgroundGeofencing(true);
    await controller.setZoneMonitoring(false);
    await controller.setBackgroundGeofencing(false);
    expect(controller.zoneMonitoring, isFalse);
    expect(controller.backgroundGeofencing, isFalse);
  });

  test('background geofences follow zone and toggle changes', () async {
    final (controller, _, geofences) = await loaded();
    await controller.addZone(name: 'Bar', latitude: 22.5, longitude: 88.3);
    await Future<void>.delayed(Duration.zero);
    expect(geofences.synced, isEmpty);

    await controller.setBackgroundGeofencing(true);
    await Future<void>.delayed(Duration.zero);
    expect(geofences.synced.last, ['Bar']);

    await controller.addZone(name: 'Dealer', latitude: 22.6, longitude: 88.4);
    await Future<void>.delayed(Duration.zero);
    expect(geofences.synced.last, ['Bar', 'Dealer']);

    final clearsBefore = geofences.clears;
    await controller.setBackgroundGeofencing(false);
    await Future<void>.delayed(Duration.zero);
    expect(geofences.clears, clearsBefore + 1);
  });

  test('backup format 4 round-trips zones and merges by ID', () async {
    final (controller, _, _) = await loaded();
    final zone = await controller.addZone(
      name: 'Bar',
      latitude: 22.5,
      longitude: 88.3,
    );
    final service = BackupService();
    final payload = service.buildBackupPayload(
      controller.events,
      preferences: controller.portablePreferences,
      zones: controller.zones,
    );
    expect(payload['version'], 4);
    final preview = service.validateBackupJson(jsonEncode(payload));
    expect(preview.zones.single.id, zone.id);

    final (fresh, _, _) = await loaded();
    await fresh.mergeImportedEvents(
      preview.events,
      importedZones: preview.zones,
    );
    await fresh.mergeImportedEvents(
      preview.events,
      importedZones: preview.zones,
    );
    expect(fresh.zones.map((z) => z.id), [zone.id]);
  });

  test('format 3 backups still import with no zones', () {
    final preview = BackupService().validateBackupJson(
      jsonEncode({'version': 3, 'events': []}),
    );
    expect(preview.zones, isEmpty);
  });

  test('a malformed zone in a backup rejects the whole import', () {
    expect(
      () => BackupService().validateBackupJson(
        jsonEncode({
          'version': 4,
          'events': [],
          'zones': [
            {'id': 'z', 'name': 'Bar', 'latitude': 200},
          ],
        }),
      ),
      throwsFormatException,
    );
  });

  test('preference import cannot switch on location tracking', () async {
    final (controller, _, _) = await loaded();
    await controller.mergeImportedEvents(
      const [],
      preferences: {'zoneMonitoring': true, 'backgroundGeofencing': true},
      restorePreferences: true,
    );
    expect(controller.zoneMonitoring, isFalse);
    expect(controller.backgroundGeofencing, isFalse);
  });
}
