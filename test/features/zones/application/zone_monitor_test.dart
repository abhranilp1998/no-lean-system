import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/zones/application/zone_monitor.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/services/location_service.dart';

import '../../../support/fake_location.dart';

void main() {
  final now = DateTime(2026, 10, 8, 18);
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
      now: () => now,
    );

    await monitor.setActive(true, const []);
    expect(monitor.isRunning, isFalse);

    await monitor.setActive(true, [zone]);
    expect(monitor.isRunning, isTrue);
    await monitor.setActive(true, [zone]); // idempotent
    expect(location.streamListens, 1);
    expect(location.currentFixRequests, 1);

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
    expect(location.currentFixRequests, 0);
  });

  test(
    'checks a stationary position on activation without Locate me or a stream event',
    () async {
      final location = FakeLocationService(fix: fixAt(22.5701));
      final entered = <String>[];
      final monitor = ZoneMonitor(
        location: location,
        onEnter: (z) => entered.add(z.name),
        now: () => now,
      );
      addTearDown(monitor.stop);
      await monitor.setActive(true, [zone]);
      await Future<void>.delayed(Duration.zero);
      expect(entered, ['Bar']);
      location.controller.add(fixAt(22.5701));
      await Future<void>.delayed(Duration.zero);
      expect(entered, ['Bar']);
    },
  );

  test(
    'a stopped monitor cannot restart when its permission check completes late',
    () async {
      final pending = Completer<LocationAccess>();
      final location = FakeLocationService(accessResult: () => pending.future);
      final monitor = ZoneMonitor(
        location: location,
        onEnter: (_) {},
        now: () => now,
      );
      final start = monitor.setActive(true, [zone]);
      await monitor.stop();
      pending.complete(LocationAccess.whileInUse);
      await start;
      expect(monitor.isRunning, isFalse);
      expect(location.streamListens, 0);
      expect(location.currentFixRequests, 0);
    },
  );

  test('a late one-shot fix after pause cannot raise an alert', () async {
    final pending = Completer<LocationFix?>();
    final location = FakeLocationService(
      currentFixResult: () => pending.future,
    );
    final entered = <String>[];
    final monitor = ZoneMonitor(
      location: location,
      onEnter: (z) => entered.add(z.name),
      now: () => now,
    );
    await monitor.setActive(true, [zone]);
    await monitor.stop();
    pending.complete(fixAt(22.5701));
    await Future<void>.delayed(Duration.zero);
    expect(entered, isEmpty);
  });

  test(
    'resume requests a new fix and rejects stale last-known or inaccurate positions',
    () async {
      final location = FakeLocationService(
        fix: LocationFix(
          latitude: zone.latitude,
          longitude: zone.longitude,
          accuracyMeters: 10,
          at: now.subtract(const Duration(minutes: 10)),
        ),
      );
      final entered = <String>[];
      final monitor = ZoneMonitor(
        location: location,
        onEnter: (z) => entered.add(z.name),
        now: () => now,
      );
      addTearDown(monitor.stop);
      await monitor.setActive(true, [zone]);
      await Future<void>.delayed(Duration.zero);
      expect(entered, isEmpty);
      await monitor.stop();
      location.fix = LocationFix(
        latitude: zone.latitude,
        longitude: zone.longitude,
        accuracyMeters: 300,
        at: now,
      );
      await monitor.setActive(true, [zone]);
      await Future<void>.delayed(Duration.zero);
      expect(entered, isEmpty);
      expect(location.currentFixRequests, 2);
      location.controller.add(fixAt(22.5701));
      await Future<void>.delayed(Duration.zero);
      expect(entered, ['Bar']);
    },
  );

  test('initial GPS failure leaves the live stream running', () async {
    final location = FakeLocationService(
      currentFixResult: () async => throw StateError('GPS timeout'),
    );
    final entered = <String>[];
    final monitor = ZoneMonitor(
      location: location,
      onEnter: (z) => entered.add(z.name),
      now: () => now,
    );
    addTearDown(monitor.stop);
    await monitor.setActive(true, [zone]);
    await Future<void>.delayed(Duration.zero);
    expect(monitor.isRunning, isTrue);
    location.controller.add(fixAt(22.5701));
    await Future<void>.delayed(Duration.zero);
    expect(entered, ['Bar']);
  });

  test(
    'a delayed older outside fix cannot clear newer inside presence',
    () async {
      final entered = <String>[];
      final tracker = ZonePresenceTracker();
      final monitor = ZoneMonitor(
        location: FakeLocationService(),
        onEnter: (z) => entered.add(z.name),
        now: () => now,
        tracker: tracker,
      );
      addTearDown(monitor.stop);
      await monitor.setActive(true, [zone]);
      monitor.handleFix(fixAt(22.5701));
      monitor.handleFix(
        LocationFix(
          latitude: 22.58,
          longitude: zone.longitude,
          accuracyMeters: 15,
          at: now.subtract(const Duration(seconds: 30)),
        ),
      );
      expect(tracker.insideZoneIds, contains(zone.id));
      monitor.handleFix(fixAt(22.5701));
      expect(entered, ['Bar']);
    },
  );
}
