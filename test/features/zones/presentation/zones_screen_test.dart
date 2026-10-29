import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/presentation/zones_screen.dart';
import 'package:no_lean/features/zones/services/location_service.dart';
import 'package:no_lean/features/zones/services/map_tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_location.dart';
import '../../../support/recovery_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
  });

  final here = LocationFix(
    latitude: 22.5726,
    longitude: 88.3639,
    accuracyMeters: 12,
    at: DateTime(2026, 10, 8, 12),
  );

  Future<(ProviderContainer, FakeLocationService)> pumpZones(
    WidgetTester tester, {
    TileProvider? tiles,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final location = FakeLocationService(fix: here);
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith(
          (ref) => RecoveryController(
            store: MemoryRecoveryStore(),
            relapseLock: FakeRelapseLock(),
          ),
        ),
        locationServiceProvider.overrideWithValue(location),
        mapTileProviderProvider.overrideWith((ref) async => tiles),
      ],
    );
    addTearDown(container.dispose);
    await container.read(recoveryProvider).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: const ZonesScreen(),
        ),
      ),
    );
    await tester.pump();
    return (container, location);
  }

  testWidgets('Zones opens location history without creating a visit', (
    tester,
  ) async {
    final (container, _) = await pumpZones(tester);
    final c = container.read(recoveryProvider);
    final before = c.events.map((e) => e.toJson()).toList();
    await tester.tap(find.byKey(const ValueKey('zones-location-history')));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar))).index,
      2,
    );
    expect(c.events.map((e) => e.toJson()).toList(), before);
  });

  testWidgets('PIN HERE marks a zone at the current fix without any network', (
    tester,
  ) async {
    final (container, _) = await pumpZones(tester);
    expect(find.text('OFFLINE GRID'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('zones-pin-here')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('zone-name')),
      'Corner pharmacy',
    );
    await tester.tap(find.byKey(const ValueKey('zone-save')));
    await tester.pumpAndSettle();

    final zones = container.read(recoveryProvider).zones;
    expect(zones, hasLength(1));
    expect(zones.single.name, 'Corner pharmacy');
    expect(zones.single.latitude, closeTo(here.latitude, 1e-9));
    expect(find.text('Corner pharmacy'), findsOneWidget);
    expect(find.textContaining('you are inside'), findsOneWidget);
  });

  testWidgets('long-press on the offline map opens the zone editor', (
    tester,
  ) async {
    final (container, _) = await pumpZones(tester);
    await tester.longPress(find.byKey(const ValueKey('zones-map')));
    await tester.pumpAndSettle();
    expect(find.text('MARK DANGER ZONE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('zone-save')));
    await tester.pump();
    expect(find.textContaining('Name it in'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('zone-name')), 'Bar');
    await tester.tap(find.byKey(const ValueKey('zone-save')));
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).zones.single.name, 'Bar');
  });

  testWidgets('in-app alerts need foreground permission and turn off freely', (
    tester,
  ) async {
    final (container, location) = await pumpZones(tester);
    final toggle = find.byKey(const ValueKey('zone-monitoring-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();

    location.current = LocationAccess.denied;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).zoneMonitoring, isFalse);
    expect(find.textContaining('Location was not granted'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(ZonesScreen)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    location.onRequestForeground = LocationAccess.whileInUse;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).zoneMonitoring, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).zoneMonitoring, isFalse);
  });

  testWidgets('background alerts: disclosure first, permission, one-tap off', (
    tester,
  ) async {
    final (container, location) = await pumpZones(tester);
    final toggle = find.byKey(const ValueKey('background-geofence-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // Nothing is requested before the user reads the disclosure.
    expect(find.byKey(const ValueKey('geofence-disclosure')), findsOneWidget);
    expect(find.textContaining('Nothing is uploaded'), findsOneWidget);
    expect(container.read(recoveryProvider).backgroundGeofencing, isFalse);

    // "While in use" only: stays off and offers system settings.
    location.onRequestBackground = LocationAccess.whileInUse;
    await tester.ensureVisible(find.byKey(const ValueKey('geofence-allow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('geofence-allow')));
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).backgroundGeofencing, isFalse);
    await tester.ensureVisible(find.byKey(const ValueKey('geofence-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('geofence-settings')));
    expect(location.settingsOpened, 1);

    location.onRequestBackground = LocationAccess.always;
    await tester.ensureVisible(find.byKey(const ValueKey('geofence-allow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('geofence-allow')));
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).backgroundGeofencing, isTrue);
    expect(find.byKey(const ValueKey('geofence-disclosure')), findsNothing);

    ScaffoldMessenger.of(
      tester.element(find.byType(ZonesScreen)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(recoveryProvider).backgroundGeofencing, isFalse);
  });

  testWidgets('no tile provider: offline grid only, no attribution', (
    tester,
  ) async {
    await pumpZones(tester);
    await tester.pump();
    expect(find.byType(TileLayer), findsNothing);
    expect(find.text('OFFLINE GRID'), findsOneWidget);
    expect(find.byKey(const ValueKey('osm-attribution')), findsNothing);
  });

  testWidgets('street tiles: OSM layer, identified client, visible credit', (
    tester,
  ) async {
    await pumpZones(tester, tiles: _MemoryTiles(_transparentPng));
    await tester.pump();
    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.urlTemplate, osmTileUrl);
    expect(layer.urlTemplate, startsWith('https://tile.openstreetmap.org/'));
    expect(
      layer.tileProvider.headers['User-Agent'],
      contains(mapUserAgentPackage),
    );
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.text('OSM // LIVE + CACHE'), findsOneWidget);
  });

  testWidgets('failing tiles fall back to the grid; pins still work', (
    tester,
  ) async {
    final (container, _) = await pumpZones(
      tester,
      tiles: _MemoryTiles(Uint8List.fromList([1, 2, 3, 4])),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.text('NO SIGNAL // GRID FALLBACK'), findsOneWidget);
    // Attribution stays while the street layer is configured.
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey('zones-map')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('zone-name')), 'Corner');
    await tester.tap(find.byKey(const ValueKey('zone-radius-500')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('zone-radius-value'))).data,
      '500 M',
    );
    await tester.tap(find.byKey(const ValueKey('zone-save')));
    await tester.pumpAndSettle();
    final zone = container.read(recoveryProvider).zones.single;
    expect(zone.name, 'Corner');
    expect(zone.radiusMeters, 500);
    expect(find.text('CORNER'), findsOneWidget); // pin label on the map
  });

  testWidgets('street tiles switch: off means grid only and no tile source', (
    tester,
  ) async {
    var providerReads = 0;
    final location = FakeLocationService(fix: here);
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith(
          (ref) => RecoveryController(
            store: MemoryRecoveryStore(),
            relapseLock: FakeRelapseLock(),
          ),
        ),
        locationServiceProvider.overrideWithValue(location),
        mapTileProviderProvider.overrideWith((ref) async {
          providerReads++;
          return _MemoryTiles(_transparentPng);
        }),
      ],
    );
    addTearDown(container.dispose);
    final recovery = container.read(recoveryProvider);
    await recovery.load();
    await recovery.setStreetTiles(false);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: const ZonesScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(providerReads, 0);
    expect(find.byType(TileLayer), findsNothing);
    expect(find.text('TILES OFF // NO NETWORK'), findsOneWidget);
    expect(find.byKey(const ValueKey('osm-attribution')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('map-tiles-toggle')));
    await tester.pump();
    await tester.pump();
    expect(recovery.streetTiles, isTrue);
    expect(providerReads, 1);
    expect(find.byType(TileLayer), findsOneWidget);
    expect(find.text('OSM // LIVE + CACHE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('map-tiles-toggle')));
    await tester.pump();
    await tester.pump();
    expect(recovery.streetTiles, isFalse);
    expect(find.byType(TileLayer), findsNothing);
  });
}

final _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _MemoryTiles extends TileProvider {
  _MemoryTiles(this.bytes);

  final Uint8List bytes;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(bytes);
}
