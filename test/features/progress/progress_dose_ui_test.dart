import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/progress/domain/heat_map_data.dart';
import 'package:no_lean/features/progress/presentation/progress_screen.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

import '../../support/recovery_fakes.dart';

DateTime _day(int daysAgo, [int hour = 21]) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo, hour);
}

Map<String, dynamic> _relapse(
  String id,
  DateTime at,
  Map<String, dynamic> metadata,
) => {
  'id': id,
  'type': 'relapse',
  'timestamp': at.toIso8601String(),
  'metadata': {'relapseType': 'fullLean', ...metadata},
};

String _state() => jsonEncode({
  'stateVersion': 12,
  'dailySpend': 0,
  'events': [
    {
      'id': 'base',
      'type': 'recoveryStart',
      'timestamp': _day(60).toIso8601String(),
      'metadata': {},
    },
    _relapse('r1', _day(10), {
      'amount': 100,
      'unit': 'ml',
      'cost': 200,
      'stress': 3,
    }),
    _relapse('r2', _day(8), {
      'amount': 1,
      'unit': 'bottle',
      'amountMl': 100,
      'bottleMl': 100,
      'cost': 200,
    }),
    _relapse('r3', _day(3), {'amount': 150, 'unit': 'ml', 'cost': 300}),
    {
      ..._relapse('b1', _day(5), {'amount': 2, 'unit': 'tablet'}),
      'metadata': {'relapseType': 'benzo', 'amount': 2, 'unit': 'tablet'},
    },
  ],
});

Future<RecoveryController> pumpProgress(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = RecoveryController(
    store: MemoryRecoveryStore(_state()),
    relapseLock: FakeRelapseLock(),
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
        home: const Scaffold(body: ProgressScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Progress opens recovery history without changing progress', (
    tester,
  ) async {
    final c = await pumpProgress(tester);
    final before = c.events.map((e) => e.toJson()).toList();
    await tester.tap(find.byKey(const ValueKey('progress-recovery-history')));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar))).index,
      0,
    );
    expect(c.events.map((e) => e.toJson()).toList(), before);
  });

  testWidgets('heat map modes switch and the weekday card follows', (
    tester,
  ) async {
    await pumpProgress(tester);
    expect(find.byKey(const ValueKey('heatmap-grid-days')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('heatmap-mode-amount')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('heatmap-grid-amount')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'amount 150 ml')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('heatmap-mode-cost')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'cost ₹300')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('weekday-peak'))).data,
      startsWith('LOW DATA // 3 days logged'),
    );
  });

  testWidgets('money card charts real costs without a daily spend', (
    tester,
  ) async {
    await pumpProgress(tester);
    await reveal(tester, find.byKey(const ValueKey('money-basis')));
    expect(find.byKey(const ValueKey('money-chart')), findsOneWidget);
    expect(find.text('LOST = ₹700 RECORDED'), findsOneWidget);
    expect(find.text('FULL LEAN ₹700'), findsOneWidget);
  });

  testWidgets('per-type card keeps tablets out of ml', (tester) async {
    await pumpProgress(tester);
    final lean = find.byKey(const ValueKey('relapse-type-fullLean'));
    await reveal(tester, lean);
    final text = tester.widget<Text>(lean).data!;
    expect(text, contains('3×'));
    expect(text, contains('350 ml total'));
    expect(text, contains('₹700 recorded'));
    final benzo = tester
        .widget<Text>(find.byKey(const ValueKey('relapse-type-benzo')))
        .data!;
    expect(benzo, contains('2 tablets'));
    expect(benzo, isNot(contains('ml')));
  });

  testWidgets('WHY sheet explains; dismiss hides until evidence changes', (
    tester,
  ) async {
    final c = await pumpProgress(tester);
    const id = 'escalation-fullLean-ml';
    final card = find.byKey(const ValueKey('insight-$id'));
    await reveal(tester, card);
    expect(find.text('FULL LEAN DOSE UP 50%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('insight-confidence-$id')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('insight-why-button-$id')));
    await tester.pumpAndSettle();
    expect(find.text('WHY THIS INSIGHT'), findsOneWidget);
    expect(find.textContaining('CONFIDENCE // EARLY SIGNAL'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('insight-dismiss')));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(c.dismissedInsights[id], 'r3');
    final restore = find.byKey(const ValueKey('insights-restore'));
    await reveal(tester, restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(c.dismissedInsights, isEmpty);
    expect(card, findsOneWidget);
  });

  test('weekday summary sums per weekday and needs 5 days for a peak', () {
    final now = DateTime(2026, 10, 9, 22); // Friday
    RecoveryEvent craving(DateTime at) => RecoveryEvent.fromJson({
      'id': 'c${at.millisecondsSinceEpoch}',
      'type': 'craving',
      'timestamp': at.toIso8601String(),
      'metadata': {'intensity': 5, 'trigger': 'Habit'},
    });
    final fridays = [
      for (var w = 0; w < 4; w++) craving(DateTime(2026, 10, 9 - 7 * w, 20)),
    ];
    final monday = craving(DateTime(2026, 10, 5, 20));
    final summary = weekdaySummary(HeatMapMode.count, [
      ...fridays,
      monday,
    ], now: now);
    expect(summary.dataDays, 5);
    expect(summary.stats[DateTime.friday - 1].value, 4);
    expect(summary.peak!.label, 'FRI');
    expect(weekdaySummary(HeatMapMode.count, fridays, now: now).peak, isNull);
  });
}
