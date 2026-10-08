// Captures the key screens through the integration driver
// (screenshots/<name>.png next to the driver). Runs with seeded state:
//
//   flutter drive --profile --driver test_driver/integration_test.dart \
//     --target integration_test/screens_flow_test.dart -d emulator-5554
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:no_lean/features/progress/presentation/progress_screen.dart';
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

const _lat = 22.5726;
const _lng = 88.3639;

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await tester.pump();
  }
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
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('key screens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 12));
    final recovery = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
    );
    await recovery.load();
    final minute = now.hour * 60 + now.minute;
    await recovery.updateRiskWindow(
      RiskWindow(
        startMinutes: (minute + 180) % RiskWindow.minutesPerDay,
        endMinutes: (minute + 240) % RiskWindow.minutesPerDay,
      ),
    );
    await recovery.mergeImportedEvents(
      [
        RecoveryEvent.create(
          type: RecoveryEventType.recoveryStart,
          timestamp: start,
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: now.subtract(const Duration(days: 8, hours: 3)),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: now.subtract(const Duration(days: 8, hours: 2)),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.craving,
          timestamp: now.subtract(const Duration(days: 5, hours: 1)),
          metadata: const {'intensity': 3, 'trigger': 'stress'},
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.zoneEntry,
          timestamp: now.subtract(const Duration(days: 2, hours: 4)),
          metadata: const {
            'zoneId': 'z1',
            'zoneName': 'Park Street',
            'source': 'app',
          },
        ),
      ],
      pin: null,
      tryBiometrics: true,
    );
    await recovery.updateDailySpend(400);
    await recovery.syncMilestones();
    final location = FakeLocationService(
      fix: LocationFix(
        latitude: _lat,
        longitude: _lng,
        accuracyMeters: 10,
        at: now,
      ),
    );
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
    await binding.convertFlutterSurfaceToImage();
    await _waitFor(tester, find.text('THE COUNTER'));
    await _settle(tester, 16); // let the celebration settle
    // Seeded history crosses 7 days clean: the milestone celebrates once.
    final dismiss = find.byKey(const ValueKey('milestone-dismiss'));
    if (dismiss.evaluate().isNotEmpty) {
      await binding.takeScreenshot('01_milestone_celebration');
      await tester.tap(dismiss);
      await _settle(tester, 8);
    }
    expect(dismiss, findsNothing);
    await binding.takeScreenshot('01_dashboard');

    await tester.tap(find.text('Progress'));
    await _settle(tester);
    final chart = find.byKey(const ValueKey('money-chart'));
    final progressList = find
        .descendant(
          of: find.byType(ProgressScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(chart, 300, scrollable: progressList);
    await tester.ensureVisible(chart);
    await _settle(tester, 6);
    await binding.takeScreenshot('02_money_chart');

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
    await _settle(tester, 8);
    await binding.takeScreenshot('03_map');

    await tester.longPress(find.byKey(const ValueKey('zones-map')));
    await _waitFor(tester, find.byKey(const ValueKey('zone-name')));
    await tester.enterText(
      find.byKey(const ValueKey('zone-name')),
      'Park Street',
    );
    await tester.tap(find.byKey(const ValueKey('zone-radius-200')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('zone-save')));
    await _waitFor(tester, find.text('1/20 ARMED'));
    await _settle(tester, 8);
    await binding.takeScreenshot('04_map_zone');

    // Tiles off: grid only, no tile layer, no attribution, no network.
    await tester.tap(find.byKey(const ValueKey('map-tiles-toggle')));
    await _waitFor(tester, find.text('TILES OFF // NO NETWORK'));
    expect(find.byKey(const ValueKey('osm-tiles')), findsNothing);
    expect(find.byKey(const ValueKey('osm-attribution')), findsNothing);
    await _settle(tester, 4);
    await binding.takeScreenshot('05_map_tiles_off');
    await tester.tap(find.byKey(const ValueKey('map-tiles-toggle')));
    await _settle(tester, 4);

    Navigator.of(tester.element(find.byKey(const ValueKey('zones-map')))).pop();
    await _settle(tester);
    await recovery.setZoneMonitoring(true);
    await _settle(tester);
    location.controller.add(
      LocationFix(latitude: _lat, longitude: _lng, accuracyMeters: 10, at: now),
    );
    await _waitFor(tester, find.byKey(const ValueKey('zone-alert-screen')));
    await binding.takeScreenshot('06_zone_alert');

    await tester.tap(find.byKey(const ValueKey('zone-alert-sos')));
    await _waitFor(tester, find.byKey(const ValueKey('sos-screen')));
    await _settle(tester, 6);
    await binding.takeScreenshot('07_sos');
    await tester.tap(find.byKey(const ValueKey('sos-close')));
    await _settle(tester);
    await recovery.setZoneMonitoring(false);
    await _settle(tester, 3);
  });
}
