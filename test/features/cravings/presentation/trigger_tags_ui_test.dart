import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/cravings/presentation/craving_dialog.dart';
import 'package:no_lean/features/cravings/presentation/craving_wave_screen.dart';
import 'package:no_lean/features/cravings/presentation/cravings_screen.dart';
import 'package:no_lean/features/plans/presentation/if_then_plans_screen.dart';
import 'package:no_lean/features/plans/presentation/plan_card.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';
import 'package:no_lean/features/recovery/domain/trigger_tags.dart';
import 'package:no_lean/features/zones/domain/zone_alert_copy.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/presentation/zone_alert_screen.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  // Outside the default 17:00-21:00 risk window.
  final now = DateTime(2026, 11, 26, 12);

  Future<RecoveryController> pump(
    WidgetTester tester,
    Widget home, {
    Future<void> Function(RecoveryController)? seed,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => now,
      cancelUseCheck: () async {},
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
    );
    await c.load();
    await seed?.call(c);
    final container = ProviderContainer(
      overrides: [recoveryProvider.overrideWith((ref) => c)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildNoLeanTheme(), home: home),
      ),
    );
    await tester.pump();
    return c;
  }

  Widget logButton() => Consumer(
    builder: (context, ref, _) => Scaffold(
      body: Center(
        child: TextButton(
          key: const ValueKey('log'),
          onPressed: () => showCravingDialog(context, ref),
          child: const Text('LOG'),
        ),
      ),
    ),
  );

  Future<void> logCraving(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('log')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('LOG IT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOG IT'));
    await tester.pumpAndSettle();
  }

  CravingEntry? lastCraving(RecoveryController c) => c.cravings.firstOrNull;

  testWidgets('after logging, three taps tag the craving and close the sheet', (
    tester,
  ) async {
    final c = await pump(tester, logButton());
    await logCraving(tester);
    expect(find.byKey(const ValueKey('trigger-tags')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag-mood-bored')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tag-with-alone')));
    await tester.pump();
    expect(find.byKey(const ValueKey('trigger-tags')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('tag-cash-plenty')));
    await tester.tap(find.byKey(const ValueKey('tag-cash-plenty')));
    await tester.pumpAndSettle();
    // The third tap closes it by itself.
    expect(find.byKey(const ValueKey('trigger-tags')), findsNothing);

    final meta = c.events.lastWhere((e) => e.type.name == 'craving').metadata;
    expect(meta['mood'], 'bored');
    expect(meta['withWho'], 'alone');
    expect(meta['cash'], 'plenty');
    expect(
      meta['trigger'],
      'After Work',
      reason: 'the log itself is untouched',
    );
    expect(lastCraving(c), isNotNull);
  });

  testWidgets('skipping saves nothing and costs nothing', (tester) async {
    final c = await pump(tester, logButton());
    await logCraving(tester);
    await tester.tap(find.byKey(const ValueKey('trigger-tags-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trigger-tags')), findsNothing);
    final meta = c.events.lastWhere((e) => e.type.name == 'craving').metadata;
    for (final k in ['mood', 'cash', 'withWho', 'place', 'taggedAt']) {
      expect(meta.containsKey(k), isFalse, reason: k);
    }
  });

  testWidgets('tapping a chip again un-tags it', (tester) async {
    final c = await pump(tester, logButton());
    await logCraving(tester);
    await tester.tap(find.byKey(const ValueKey('tag-mood-low')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tag-mood-low')));
    await tester.pump();
    final meta = c.events.lastWhere((e) => e.type.name == 'craving').metadata;
    expect(meta.containsKey('mood'), isFalse);
  });

  testWidgets('a matching plan appears in the sheet once the mood is tagged', (
    tester,
  ) async {
    await pump(
      tester,
      logButton(),
      seed: (c) async {
        await c.addIfThenPlan(
          ifText: 'I feel bored',
          thenText: 'call my brother',
          mood: 'bored',
        );
      },
    );
    await logCraving(tester);
    expect(find.byKey(const ValueKey('trigger-tags-plan')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-mood-bored')));
    await tester.pump();
    expect(find.byKey(const ValueKey('trigger-tags-plan')), findsOneWidget);
    expect(
      find.text('If I feel bored, then I will call my brother.'),
      findsOneWidget,
    );
  });

  testWidgets('writing a plan from the plans screen saves it', (tester) async {
    final c = await pump(tester, const IfThenPlansScreen());
    expect(find.byKey(const ValueKey('plans-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-add')));
    await tester.pumpAndSettle();

    // Empty form: gentle error, nothing saved.
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pump();
    expect(find.byKey(const ValueKey('plan-error')), findsOneWidget);
    expect(c.ifThenPlans, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('plan-if')),
      "I'm near the shop",
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-then')),
      'cross the road',
    );
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    expect(
      c.ifThenPlans.single.sentence,
      "If I'm near the shop, then I will cross the road.",
    );
    expect(
      find.byKey(ValueKey('plan-${c.ifThenPlans.single.id}')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ValueKey('plan-delete-${c.ifThenPlans.single.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-delete-confirm')));
    await tester.pumpAndSettle();
    expect(c.ifThenPlans, isEmpty);
  });

  testWidgets('a suggested situation opens the editor already filled in', (
    tester,
  ) async {
    await pump(
      tester,
      const IfThenPlansScreen(
        suggestedIf: "I'm bored, alone and with cash on me",
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-editor')), findsOneWidget);
    expect(find.text("I'm bored, alone and with cash on me"), findsOneWidget);
  });

  testWidgets('the zone alert screen shows the plan for that place', (
    tester,
  ) async {
    final zone = DangerZone(
      id: 'z1',
      name: 'Bus stand',
      latitude: 12.9,
      longitude: 77.5,
      radiusMeters: 200,
      createdAt: DateTime(2026, 11, 1),
    );
    final c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await c.load();
    final plan = await c.addIfThenPlan(
      ifText: "I'm at the bus stand",
      thenText: 'cross the road',
      zoneId: 'z1',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: ZoneAlertScreen(
          copy: buildZoneAlertCopy(zone: zone, now: now, plans: [plan]),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('zone-alert-plan')), findsOneWidget);
    expect(
      find.text("If I'm at the bus stand, then I will cross the road."),
      findsOneWidget,
    );
    // The plan is not also repeated inside the paragraph.
    expect(find.textContaining('Your plan:'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: ZoneAlertScreen(
          copy: buildZoneAlertCopy(zone: zone, now: now),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('zone-alert-plan')), findsNothing);
  });

  testWidgets('the home card shows the plan only inside the risk window', (
    tester,
  ) async {
    Future<void> check(DateTime at, {required bool shown}) async {
      final c = RecoveryController(
        store: MemoryRecoveryStore(),
        relapseLock: FakeRelapseLock(),
        now: () => at,
      );
      await c.load();
      await c.addIfThenPlan(ifText: 'it is evening', thenText: 'go for a walk');
      final container = ProviderContainer(
        overrides: [recoveryProvider.overrideWith((ref) => c)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildNoLeanTheme(),
            home: const Scaffold(body: PlanNowCard()),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('plan-now-card')),
        shown ? findsOneWidget : findsNothing,
      );
    }

    await check(DateTime(2026, 11, 26, 18), shown: true);
    await check(DateTime(2026, 11, 26, 11), shown: false);
  });

  testWidgets('the craving screen links to plans and shows the pattern nudge', (
    tester,
  ) async {
    await pump(
      tester,
      const CravingsScreen(),
      seed: (c) async {
        final id = await c.recordCraving(
          CravingEntry(
            intensity: 6,
            trigger: 'Habit',
            note: '',
            createdAt: DateTime(2026, 11, 25, 12),
          ),
        );
        await c.recordTriggerTags(id, const TriggerTags(mood: 'bored'));
      },
    );
    expect(find.byKey(const Key('open-if-then-plans')), findsOneWidget);
    expect(find.byKey(const ValueKey('trigger-pattern-card')), findsOneWidget);
    expect(find.textContaining('Tag 5 more cravings'), findsOneWidget);
  });

  testWidgets('the wave screen shows a general plan', (tester) async {
    await pump(
      tester,
      const CravingWaveScreen(),
      seed: (c) async {
        await c.addIfThenPlan(
          ifText: 'the craving peaks',
          thenText: 'drink water and breathe',
        );
      },
    );
    expect(find.byKey(const ValueKey('wave-plan')), findsOneWidget);
  });
}
