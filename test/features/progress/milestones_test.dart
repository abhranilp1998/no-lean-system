import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:no_lean/app/no_lean_app.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/progress/presentation/milestone_celebration.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/milestones.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

import '../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime(2026, 9, 1, 9);

  Future<(RecoveryController, MemoryRecoveryStore)> loaded(
    DateTime Function() clock,
  ) async {
    final store = MemoryRecoveryStore(
      jsonEncode({
        'stateVersion': RecoveryController.stateVersion,
        'events': [
          RecoveryEvent.create(
            type: RecoveryEventType.recoveryStart,
            timestamp: start,
          ).toJson(),
        ],
      }),
    );
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: clock,
    );
    await controller.load();
    return (controller, store);
  }

  List<int> milestoneDays(RecoveryController c) => [
    for (final e in c.events)
      if (e.type == RecoveryEventType.milestone) e.metadata['days'] as int,
  ];

  test('due milestones respect the exact moment a day count is reached', () {
    final events = <RecoveryEvent>[];
    expect(
      dueMilestones(
        events: events,
        lastDose: start,
        now: start.add(const Duration(days: 3, seconds: -1)),
      ),
      isEmpty,
    );
    expect(
      dueMilestones(
        events: events,
        lastDose: start,
        now: start.add(const Duration(days: 7)),
      ).map((m) => m.days),
      [3, 7],
    );
  });

  test('milestones from an earlier streak do not count again', () {
    final old = RecoveryEvent.create(
      type: RecoveryEventType.milestone,
      timestamp: start.subtract(const Duration(days: 20)),
      metadata: {'days': 3},
    );
    expect(
      dueMilestones(
        events: [old],
        lastDose: start,
        now: start.add(const Duration(days: 4)),
      ).map((m) => m.days),
      [3],
    );
  });

  test('the controller records each milestone once, stamped when reached, '
      'and queues one celebration for the highest', () async {
    var now = start.add(const Duration(days: 2));
    final (controller, store) = await loaded(() => now);
    expect(await controller.syncMilestones(), isNull);
    expect(milestoneDays(controller), isEmpty);

    now = start.add(const Duration(days: 8, hours: 2));
    expect(await controller.syncMilestones(), 7);
    expect(milestoneDays(controller), [3, 7]);
    expect(controller.pendingCelebration, 7);
    final seven = controller.events.lastWhere(
      (e) => e.type == RecoveryEventType.milestone,
    );
    expect(seven.timestamp, start.add(const Duration(days: 7)));
    expect(seven.metadata['label'], 'FIRST WEEK');
    expect(seven.metadata['source'], 'auto');

    // Idempotent: nothing new, no extra write.
    final writes = store.writes;
    expect(await controller.syncMilestones(), isNull);
    expect(store.writes, writes);
    expect(milestoneDays(controller), [3, 7]);

    controller.consumeCelebration();
    expect(controller.pendingCelebration, isNull);

    // Persisted and reloaded without duplicates.
    final reloaded = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await reloaded.load();
    expect(await reloaded.syncMilestones(), isNull);
    expect(milestoneDays(reloaded), [3, 7]);
  });

  Future<void> pumpCelebration(WidgetTester tester, {required bool reduce}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildNoLeanTheme(reduceMotion: reduce),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMilestoneCelebration(context, days: 7),
              child: const Text('GO'),
            ),
          ),
        ),
      );

  testWidgets('celebration animates and dismisses', (tester) async {
    await pumpCelebration(tester, reduce: false);
    await tester.tap(find.text('GO'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 230));
    expect(find.text('7D'), findsWidgets);
    expect(find.text('FIRST WEEK'), findsOneWidget);
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('milestone-burst')),
                )
                .painter!
            as MilestoneBurstPainter;
    expect(painter.animated, isTrue);
    // Glitch layers are present while moving.
    expect(find.text('7D'), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('milestone-dismiss')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('FIRST WEEK'), findsNothing);
  });

  testWidgets('reduce motion shows a still celebration', (tester) async {
    await pumpCelebration(tester, reduce: true);
    await tester.tap(find.text('GO'));
    await tester.pump();
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('milestone-burst')),
                )
                .painter!
            as MilestoneBurstPainter;
    expect(painter.animated, isFalse);
    expect(find.text('7D'), findsOneWidget);
    // Nothing is scheduled to move: the tree settles immediately.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    await tester.tap(find.byKey(const ValueKey('milestone-dismiss')));
    await tester.pump();
    expect(find.text('FIRST WEEK'), findsNothing);
  });

  testWidgets('the shell records reached milestones and celebrates once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('no_lean/widget_actions'),
      (_) async => <String>[],
    );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final (controller, _) = await loaded(
      () => start.add(const Duration(days: 15)),
    );
    final container = ProviderContainer(
      overrides: [recoveryProvider.overrideWith((ref) => controller)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NoLeanApp()),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(milestoneDays(controller), [3, 7, 14]);
    expect(find.text('14D'), findsWidgets);
    expect(find.text('HABIT PRESSURE DROPS'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('milestone-dismiss')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('milestone-dismiss')), findsNothing);
    expect(controller.pendingCelebration, isNull);
  });
}
