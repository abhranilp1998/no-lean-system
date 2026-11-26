import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/companion/presentation/urge_surf_screen.dart';
import 'package:no_lean/features/cravings/domain/urge_ride.dart';
import 'package:no_lean/features/cravings/presentation/what_worked_card.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  late RecoveryController c;
  late List<BreathPhase> paces;
  late DateTime clock;

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    paces = [];
    clock = DateTime(2026, 11, 27, 12);
    c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
      scheduleUseCheck: (_) async => true,
      cancelUseCheck: () async {},
    );
    await c.load();
    final container = ProviderContainer(
      overrides: [recoveryProvider.overrideWith((ref) => c)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: UrgeSurfScreen(onPace: paces.add, now: () => clock),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
    );
    await c.load();
    final container = ProviderContainer(
      overrides: [recoveryProvider.overrideWith((ref) => c)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: const [WhatWorkedCard()],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('starts a 10-minute timer and pulses the breath pace', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.text('Start 10-minute timer'), findsOneWidget);
    expect(find.text('Ride it out'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('urge-ride-start')));
    await tester.pump();
    expect(find.byKey(const ValueKey('urge-ride-timer')), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect(paces, isNotEmpty);
    expect(paces.first, BreathPhase.inhale);
    clock = clock.add(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('09:56'), findsOneWidget);
    expect(paces, contains(BreathPhase.exhale));
    expect(find.text('Breathe out'), findsOneWidget);
  });

  testWidgets('at the end, Yes + Walk is saved and counted', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('urge-ride-start')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('urge-ride-already-passed')));
    await tester.pump();
    expect(find.text('Did it pass?'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('urge-ride-passed-yes')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('urge-ride-activity-walk')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('urge-ride-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.urgeRides, hasLength(1));
    expect(c.urgeRides.single.outcome, UrgeRideOutcome.yes);
    expect(c.urgeRides.single.activity, UrgeRideActivity.walk);
    expect(c.whatWorked.passed, 1);
  });

  testWidgets('the home card stays hidden until there is a ride, then ranks', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.byKey(const ValueKey('what-worked-card')), findsNothing);

    for (var i = 0; i < 3; i++) {
      await c.recordUrgeRide(
        startedAt: DateTime.now().subtract(Duration(hours: i + 1)),
        outcome: UrgeRideOutcome.yes,
        activity: UrgeRideActivity.shower,
      );
    }
    await tester.pump();
    expect(find.byKey(const ValueKey('what-worked-card')), findsOneWidget);
    expect(find.textContaining('3 of 3'), findsWidgets);
    expect(
      find.byKey(const ValueKey('what-worked-rank-shower')),
      findsOneWidget,
    );
    expect(find.text('Shower'), findsOneWidget);
  });

  testWidgets('an activity with fewer than 3 rides is not ranked yet', (
    tester,
  ) async {
    await pumpCard(tester);
    await c.recordUrgeRide(
      startedAt: DateTime.now().subtract(const Duration(hours: 1)),
      outcome: UrgeRideOutcome.yes,
      activity: UrgeRideActivity.music,
    );
    await c.recordUrgeRide(
      startedAt: DateTime.now().subtract(const Duration(hours: 2)),
      outcome: UrgeRideOutcome.yes,
      activity: UrgeRideActivity.music,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('what-worked-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('what-worked-rank-music')), findsNothing);
    expect(find.textContaining('A few more rides'), findsOneWidget);
  });
}
