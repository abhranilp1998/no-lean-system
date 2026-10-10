import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/zones/application/position_status_host.dart';
import 'package:no_lean/features/zones/domain/position_status.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/services/location_service.dart';

import '../../../support/fake_location.dart';
import '../../../support/recovery_fakes.dart';

class RecordingSink implements PositionStatusSink {
  final shown = <PositionStatusText>[];
  int cancels = 0;

  @override
  Future<void> show(PositionStatusText text) async => shown.add(text);

  @override
  Future<void> cancel() async => cancels++;
}

void main() {
  final here = LocationFix(
    latitude: 22.5726,
    longitude: 88.3639,
    accuracyMeters: 12,
    at: DateTime(2026, 10, 10, 12),
  );

  Future<(ProviderContainer, RecordingSink, FakeLocationService)> pump(
    WidgetTester tester, {
    LocationAccess access = LocationAccess.whileInUse,
    bool zone = true,
    bool hide = false,
  }) async {
    final sink = RecordingSink();
    final location = FakeLocationService(current: access, fix: here);
    final container = ProviderContainer(
      overrides: [
        recoveryProvider.overrideWith(
          (ref) => RecoveryController(
            store: MemoryRecoveryStore(),
            relapseLock: FakeRelapseLock(),
          ),
        ),
        locationServiceProvider.overrideWithValue(location),
        positionStatusSinkProvider.overrideWithValue(sink),
      ],
    );
    final recovery = container.read(recoveryProvider);
    await recovery.load();
    if (zone) {
      await recovery.addZone(
        name: 'Bar',
        latitude: here.latitude,
        longitude: here.longitude,
        radiusMeters: 200,
      );
    }
    if (hide) await recovery.setHideSensitiveNotifications(true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PositionStatusHost(child: SizedBox())),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (container, sink, location);
  }

  testWidgets('shows INSIDE even though zone monitoring is off', (
    tester,
  ) async {
    final (container, sink, _) = await pump(tester);
    addTearDown(container.dispose);
    expect(container.read(recoveryProvider).positionNotification, isTrue);
    expect(container.read(recoveryProvider).zoneMonitoring, isFalse);
    expect(sink.shown.last.title, 'INSIDE Bar');
  });

  testWidgets('reports no permission without asking for it', (tester) async {
    final (container, sink, location) = await pump(
      tester,
      access: LocationAccess.denied,
    );
    addTearDown(container.dispose);
    expect(sink.shown.single.title, 'Position: no permission');
    expect(location.streamListens, 0);
  });

  testWidgets('location off is shown', (tester) async {
    final (container, sink, _) = await pump(
      tester,
      access: LocationAccess.serviceDisabled,
    );
    addTearDown(container.dispose);
    expect(sink.shown.single.title, 'Position: location off');
  });

  testWidgets('hide sensitive posts the neutral text only', (tester) async {
    final (container, sink, _) = await pump(tester, hide: true);
    addTearDown(container.dispose);
    expect(sink.shown, isNotEmpty);
    for (final text in sink.shown) {
      expect(text.title, neutralPositionTitle);
      expect(text.body, isNot(contains('Bar')));
    }
  });

  testWidgets('cancels on pause, posts again on resume', (tester) async {
    final (container, sink, _) = await pump(tester);
    addTearDown(container.dispose);
    final before = sink.shown.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(sink.cancels, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(sink.shown.length, greaterThan(before));
    expect(sink.shown.last.title, 'INSIDE Bar');
  });

  testWidgets('turning the setting off cancels and stops updates', (
    tester,
  ) async {
    final (container, sink, location) = await pump(tester);
    addTearDown(container.dispose);
    await container.read(recoveryProvider).setPositionNotification(false);
    await tester.pump();
    expect(sink.cancels, 1);
    final count = sink.shown.length;
    location.controller.add(here);
    await tester.pump(const Duration(seconds: 20));
    expect(sink.shown.length, count);
  });

  testWidgets('leaving the zone updates at once; drift is throttled', (
    tester,
  ) async {
    final (container, sink, location) = await pump(tester);
    addTearDown(container.dispose);
    expect(sink.shown.last.title, 'INSIDE Bar');

    // ~1.1 km south: outside -> state change, posted immediately.
    location.controller.add(
      LocationFix(
        latitude: 22.5626,
        longitude: 88.3639,
        accuracyMeters: 12,
        at: DateTime(2026, 10, 10, 12, 1),
      ),
    );
    await tester.pump();
    expect(sink.shown.last.title, 'Position 22.563, 88.364');
    final count = sink.shown.length;

    // Small drift within 15 s: throttled.
    location.controller.add(
      LocationFix(
        latitude: 22.5616,
        longitude: 88.3639,
        accuracyMeters: 12,
        at: DateTime(2026, 10, 10, 12, 1, 5),
      ),
    );
    await tester.pump();
    expect(sink.shown.length, count);
  });
}
