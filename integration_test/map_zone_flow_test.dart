// On-device map and zone flows. Run on an emulator or phone:
//
//   flutter test integration_test -d emulator-5554
//
// The last test drives the real geolocator against the device's mock
// location. It only runs with --dart-define=REAL_LOCATION=true, after the
// app has been granted location and the host is feeding fixes, e.g.
// `tool/emulator_geo_walk.sh` (Kolkata, in and out of the zone).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/settings/presentation/settings_screen.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/services/location_service.dart';
import 'package:no_lean/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_location.dart';
import '../test/support/recovery_fakes.dart';

const _realLocation = bool.fromEnvironment('REAL_LOCATION');

/// Park Street, Kolkata — the same point the host scripts feed the emulator.
const _kolkataLat = 22.5726;
const _kolkataLng = 88.3639;

LocationFix _fix(double lat, double lng) => LocationFix(
  latitude: lat,
  longitude: lng,
  accuracyMeters: 10,
  at: DateTime.now(),
);

Future<RecoveryController> _controller() async {
  final controller = RecoveryController(
    store: MemoryRecoveryStore(),
    relapseLock: FakeRelapseLock(),
  );
  await controller.load();
  // Keep the risk-window lock and its alerts out of the way of the flows.
  final minute = DateTime.now().hour * 60 + DateTime.now().minute;
  await controller.updateRiskWindow(
    RiskWindow(
      startMinutes: (minute + 180) % RiskWindow.minutesPerDay,
      endMinutes: (minute + 240) % RiskWindow.minutesPerDay,
    ),
  );
  return controller;
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out waiting for $finder');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

Future<void> _openZones(WidgetTester tester) async {
  await _waitFor(tester, find.text('THE COUNTER'));
  await tester.tap(find.text('Settings'));
  await _settle(tester);
  final entry = find.byKey(const ValueKey('settings-danger-zones'));
  final settingsList = find
      .descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(entry, 300, scrollable: settingsList);
  await tester.ensureVisible(entry);
  await _settle(tester, 3);
  await tester.tap(entry);
  await _waitFor(tester, find.byKey(const ValueKey('zones-map')));
  await _settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('map: street tiles, tiles-off switch, locate and drop a zone', (
    tester,
  ) async {
    final location = FakeLocationService(fix: _fix(_kolkataLat, _kolkataLng));
    final recovery = await _controller();
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith((ref) => recovery),
        locationServiceProvider.overrideWithValue(location),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NoLeanApp()),
    );
    await _openZones(tester);

    // Street tiles are on by default: OSM layer + mandatory attribution.
    await _waitFor(tester, find.byKey(const ValueKey('osm-tiles')));
    expect(find.byKey(const ValueKey('osm-attribution')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('zones-locate')));
    await _settle(tester, 15);

    // Long-press the middle of the map (now centred on the fix).
    await tester.longPress(find.byKey(const ValueKey('zones-map')));
    await _waitFor(tester, find.byKey(const ValueKey('zone-name')));
    await tester.enterText(
      find.byKey(const ValueKey('zone-name')),
      'Corner shop',
    );
    await tester.tap(find.byKey(const ValueKey('zone-radius-200')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('zone-save')));
    await _waitFor(tester, find.text('1/20 ARMED'));

    final zone = recovery.zones.single;
    expect(zone.name, 'Corner shop');
    expect(zone.radiusMeters, 200);
    // The long-press landed near the located fix (map centre).
    expect(zone.distanceTo(_kolkataLat, _kolkataLng), lessThan(150));

    // Tiles off: the tile layer and attribution go, the grid stays.
    await tester.tap(find.byKey(const ValueKey('map-tiles-toggle')));
    await _waitFor(tester, find.text('TILES OFF // NO NETWORK'));
    expect(find.byKey(const ValueKey('osm-tiles')), findsNothing);
    expect(find.byKey(const ValueKey('osm-attribution')), findsNothing);
    expect(recovery.streetTiles, isFalse);

    await tester.tap(find.byKey(const ValueKey('map-tiles-toggle')));
    await _waitFor(tester, find.byKey(const ValueKey('osm-tiles')));
    expect(recovery.streetTiles, isTrue);
  });

  testWidgets('zone: in-app entry alerts, exits in one tap, logs name only', (
    tester,
  ) async {
    final location = FakeLocationService(fix: _fix(_kolkataLat, _kolkataLng));
    final recovery = await _controller();
    await recovery.addZone(
      name: 'Bar',
      latitude: _kolkataLat,
      longitude: _kolkataLng,
      radiusMeters: 200,
    );
    await recovery.setZoneHistory(true);
    await recovery.setZoneMonitoring(true);
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith((ref) => recovery),
        locationServiceProvider.overrideWithValue(location),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NoLeanApp()),
    );
    await _waitFor(tester, find.text('THE COUNTER'));
    await _settle(tester);
    expect(location.streamListens, 1);

    // Outside (≈1.1 km north), then walk in.
    location.controller.add(_fix(_kolkataLat + 0.01, _kolkataLng));
    await _settle(tester, 3);
    expect(find.byKey(const ValueKey('zone-alert-screen')), findsNothing);
    location.controller.add(_fix(_kolkataLat + 0.0005, _kolkataLng));
    await _waitFor(tester, find.byKey(const ValueKey('zone-alert-screen')));
    expect(find.text('DANGER ZONE // BAR'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('zone-alert-exit')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('zone-alert-screen')), findsNothing);

    final entries = recovery.events
        .where((event) => event.type == RecoveryEventType.zoneEntry)
        .toList();
    expect(entries, hasLength(1));
    expect(entries.single.metadata['zoneName'], 'Bar');
    expect(
      entries.single.metadata.keys,
      isNot(anyOf(contains('latitude'), contains('longitude'))),
    );

    await recovery.setZoneMonitoring(false);
    await _settle(tester, 3);
  });

  testWidgets(
    'real location: PIN HERE uses the device fix and the monitor alerts',
    (tester) async {
      final recovery = await _controller();
      final container = ProviderContainer(
        overrides: [recoveryProvider.overrideWith((ref) => recovery)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const NoLeanApp(),
        ),
      );
      await _openZones(tester);

      await tester.tap(find.byKey(const ValueKey('zones-pin-here')));
      await _waitFor(
        tester,
        find.byKey(const ValueKey('zone-name')),
        timeout: const Duration(seconds: 40),
      );
      await tester.enterText(
        find.byKey(const ValueKey('zone-name')),
        'Park Street',
      );
      await tester.tap(find.byKey(const ValueKey('zone-radius-200')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('zone-save')));
      await _waitFor(tester, find.text('1/20 ARMED'));

      final zone = recovery.zones.single;
      // The host walks between the zone centre and ~1 km away, so the
      // pinned fix is one of those two points.
      final nearCentre = zone.distanceTo(_kolkataLat, _kolkataLng) < 60;
      final nearOutside = zone.distanceTo(_kolkataLat + 0.01, _kolkataLng) < 60;
      expect(nearCentre || nearOutside, isTrue);
      if (nearOutside) {
        // Re-pin on the real centre so the walk crosses the boundary.
        await recovery.addZone(
          name: 'Park Street centre',
          latitude: _kolkataLat,
          longitude: _kolkataLng,
          radiusMeters: 200,
        );
      }

      Navigator.of(
        tester.element(find.byKey(const ValueKey('zones-map'))),
      ).pop();
      await _settle(tester);
      await recovery.setZoneMonitoring(true);
      await _waitFor(
        tester,
        find.byKey(const ValueKey('zone-alert-screen')),
        timeout: const Duration(seconds: 90),
      );
      expect(find.textContaining('DANGER ZONE // PARK STREET'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('zone-alert-exit')));
      await _settle(tester);
      await recovery.setZoneMonitoring(false);
      await _settle(tester, 3);
    },
    skip: !_realLocation,
  );
}
