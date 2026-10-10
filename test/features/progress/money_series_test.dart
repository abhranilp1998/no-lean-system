import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:no_lean/app/no_lean_app.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/progress/domain/money_series.dart';
import 'package:no_lean/features/progress/presentation/widgets/money_chart_card.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

import '../../support/recovery_fakes.dart';

void main() {
  final start = DateTime(2026, 10, 1, 9);
  RecoveryEvent at(RecoveryEventType type, DateTime when) =>
      RecoveryEvent.create(type: type, timestamp: when);

  test('₹0 or no history charts nothing', () {
    expect(
      cumulativeMoneySeries(
        events: [at(RecoveryEventType.recoveryStart, start)],
        dailySpend: 0,
        now: start,
      ),
      isEmpty,
    );
    expect(
      cumulativeMoneySeries(events: const [], dailySpend: 500, now: start),
      isEmpty,
    );
  });

  test('clean days add to kept, relapse days to lost, today is partial', () {
    final events = [
      at(RecoveryEventType.recoveryStart, start),
      at(RecoveryEventType.relapse, DateTime(2026, 10, 3, 22)),
      at(RecoveryEventType.relapse, DateTime(2026, 10, 3, 23)), // same day
      RecoveryEvent.create(
        type: RecoveryEventType.daySummary,
        timestamp: DateTime(2026, 10, 1),
        metadata: {'date': '2026-09-29', 'clean': false},
      ),
    ];
    final series = cumulativeMoneySeries(
      events: events,
      dailySpend: 400,
      now: DateTime(2026, 10, 5, 12),
    );
    // 29 Sep (lost), 30 Sep, 1 Oct, 2 Oct, 3 Oct (lost), 4 Oct, 5 Oct (half).
    expect(series.map((p) => p.day.day), [29, 30, 1, 2, 3, 4, 5]);
    expect(series.first.lost, 400);
    expect(series.last.lost, 800);
    expect(series.last.saved, 400 * 4 + 200);
    // Cumulative lines never go down.
    for (var i = 1; i < series.length; i++) {
      expect(series[i].saved, greaterThanOrEqualTo(series[i - 1].saved));
      expect(series[i].lost, greaterThanOrEqualTo(series[i - 1].lost));
    }
  });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildNoLeanTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets('₹0 daily spend prompts instead of charting', (tester) async {
    var tapped = 0;
    await pump(
      tester,
      MoneyChartCard(
        points: const [],
        dailySpend: 0,
        onSetSpend: () => tapped++,
      ),
    );
    expect(find.byKey(const ValueKey('money-chart')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('money-set-spend')));
    expect(tapped, 1);
  });

  testWidgets('the chart shows kept, lost and net totals', (tester) async {
    final series = cumulativeMoneySeries(
      events: [
        at(RecoveryEventType.recoveryStart, start),
        at(RecoveryEventType.relapse, DateTime(2026, 10, 2, 20)),
      ],
      dailySpend: 300,
      now: DateTime(2026, 10, 4, 23, 59),
    );
    await pump(
      tester,
      MoneyChartCard(points: series, dailySpend: 300, onSetSpend: () {}),
    );
    expect(find.byKey(const ValueKey('money-chart')), findsOneWidget);
    expect(find.text('₹300'), findsOneWidget); // lost
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dashboard asks for daily spend while it is ₹0', (
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
    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
    );
    await controller.load();
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
    final prompt = find.byKey(const ValueKey('dashboard-set-spend'));
    await tester.scrollUntilVisible(prompt, 200);
    await tester.tap(prompt);
    await tester.pumpAndSettle();
    expect(find.text('AVERAGE DAILY SPEND'), findsOneWidget);
  });
}
