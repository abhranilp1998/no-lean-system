import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/services/location_service.dart';
import 'package:no_lean/main.dart';
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

  testWidgets('entering a zone in-app interrupts, and exit is one tap', (
    tester,
  ) async {
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
      ],
    );
    addTearDown(container.dispose);
    final recovery = container.read(recoveryProvider);
    await recovery.load();
    final minute = DateTime.now().hour * 60 + DateTime.now().minute;
    await recovery.updateRiskWindow(
      RiskWindow(
        startMinutes: (minute + 180) % RiskWindow.minutesPerDay,
        endMinutes: (minute + 240) % RiskWindow.minutesPerDay,
      ),
    );
    await recovery.addZone(
      name: 'Bar',
      latitude: here.latitude,
      longitude: here.longitude,
      radiusMeters: 200,
    );
    await recovery.setZoneMonitoring(true);
    // This test counts the zone monitor's own location stream; the
    // always-on position notification has its own tests.
    await recovery.setPositionNotification(false);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NoLeanApp()),
    );
    for (
      var i = 0;
      i < 30 && find.text('THE COUNTER').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(location.streamListens, 1);

    location.controller.add(here);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zone-alert-screen')), findsOneWidget);
    expect(find.text('DANGER ZONE // BAR'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('zone-alert-exit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zone-alert-screen')), findsNothing);
    expect(find.text('THE COUNTER'), findsOneWidget);

    await recovery.setZoneMonitoring(false);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
