import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/dates/domain/high_risk_dates.dart';
import 'package:no_lean/features/dates/presentation/high_risk_dates_card.dart';
import 'package:no_lean/features/dates/presentation/high_risk_dates_screen.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recovery_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<RecoveryController> pump(
    WidgetTester t,
    Widget home, {
    DateTime? now,
    Future<void> Function(RecoveryController c)? setup,
  }) async {
    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => now ?? DateTime(2026, 11, 27, 12),
      scheduleHighRiskDateReminders: (_) async {},
      cancelHighRiskDateReminders: () async {},
    );
    await t.runAsync(controller.load);
    if (setup != null) await t.runAsync(() => setup(controller));
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [recoveryProvider.overrideWith((ref) => controller)],
        child: MaterialApp(
          theme: buildNoLeanTheme(reduceMotion: true),
          home: Scaffold(body: home),
        ),
      ),
    );
    await t.pump();
    return controller;
  }

  testWidgets('Home card lists upcoming dates and opens a plan sheet', (
    t,
  ) async {
    await pump(t, const HighRiskDatesCard());
    expect(find.byKey(const Key('high-risk-dates-card')), findsOneWidget);
    expect(find.text('Christmas'), findsOneWidget);
    expect(find.text("New Year's Eve"), findsOneWidget);

    await t.tap(find.text('MAKE A PLAN').first);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('high-risk-plan-sheet')), findsOneWidget);
    expect(find.textContaining("WHAT'S YOUR PLAN?"), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('high-risk-plan-note')),
      'Stay with family',
    );
    await t.tap(find.byKey(const Key('high-risk-plan-save')));
    await t.pumpAndSettle();
    expect(find.text('Stay with family'), findsWidgets);
    expect(find.text('SEE PLAN'), findsWidgets);
  });

  testWidgets('settings screen toggle defaults on and payday can be set', (
    t,
  ) async {
    final controller = await pump(t, const HighRiskDatesScreen());
    expect(find.byKey(const Key('high-risk-dates-screen')), findsOneWidget);
    final toggle = t.widget<SwitchListTile>(
      find.byKey(const Key('high-risk-reminders-toggle')),
    );
    expect(toggle.value, isTrue);
    expect(controller.highRiskDateReminders, isTrue);

    await t.tap(find.byKey(const Key('high-risk-payday')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('high-risk-payday-save')));
    await t.pumpAndSettle();
    expect(controller.paydayDay, 1);
    expect(find.textContaining('Day 1 each month'), findsWidgets);
  });

  testWidgets('user can add an annual custom date', (t) async {
    final controller = await pump(t, const HighRiskDatesScreen());
    await t.tap(find.byKey(const Key('high-risk-add-date')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('high-risk-add-date-sheet')), findsOneWidget);
    await t.enterText(
      find.byKey(const Key('high-risk-custom-name')),
      "Asha's birthday",
    );
    await t.tap(find.byKey(const Key('high-risk-custom-save')));
    await t.pumpAndSettle();
    expect(controller.customHighRiskDates, hasLength(1));
    expect(controller.customHighRiskDates.single.name, "Asha's birthday");
    expect(controller.customHighRiskDates.single.kind, CustomDateKind.birthday);
    expect(find.text("Asha's birthday"), findsWidgets);
  });
}
