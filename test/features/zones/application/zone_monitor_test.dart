import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/zones/application/zone_monitor.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/services/location_service.dart';

import '../../../support/fake_location.dart';

void main() {
  final zone = DangerZone(
    id: 'z1',
    name: 'Bar',
    latitude: 22.57,
    longitude: 88.36,
    radiusMeters: 200,
    createdAt: DateTime(2026, 10, 1),
  );
  LocationFix fixAt(double lat) => LocationFix(
    latitude: lat,
    longitude: 88.36,
    accuracyMeters: 15,
    at: DateTime(2026, 10, 8, 18),
  );

  test('streams only while active, with zones and permission', () async {
    final location = FakeLocationService();
    final entered = <String>[];
    final monitor = ZoneMonitor(
      location: location,
      onEnter: (z) => entered.add(z.name),
    );

    await monitor.setActive(true, const []);
    expect(monitor.isRunning, isFalse);

    await monitor.setActive(true, [zone]);
    expect(monitor.isRunning, isTrue);
    await monitor.setActive(true, [zone]); // idempotent
    expect(location.streamListens, 1);

    location.controller.add(fixAt(22.58));
    location.controller.add(fixAt(22.5701));
    await Future<void>.delayed(Duration.zero);
    expect(entered, ['Bar']);

    await monitor.setActive(false, [zone]);
    expect(monitor.isRunning, isFalse);
  });

  test('never starts without location permission', () async {
    final location = FakeLocationService(current: LocationAccess.denied);
    final monitor = ZoneMonitor(location: location, onEnter: (_) {});
    await monitor.setActive(true, [zone]);
    expect(monitor.isRunning, isFalse);
    expect(location.streamListens, 0);
  });
}
