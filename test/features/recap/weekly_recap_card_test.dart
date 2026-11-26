import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recap/domain/weekly_recap.dart';
import 'package:no_lean/features/recap/presentation/weekly_recap_card.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';

import '../../support/recap_events.dart';
import '../../support/recovery_fakes.dart';

void main() {
  testWidgets('the card shows headline, counts, and one next step', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 27, 20);
    final events = [
      startAt(DateTime(2026, 10, 1)),
      relapseAt(DateTime(2026, 11, 24, 23)),
      relapseAt(DateTime(2026, 11, 25, 22), type: 'benzo'),
      cravingAt(DateTime(2026, 11, 22, 21)),
    ];
    final recap = computeWeeklyRecap(
      events: events,
      lastDose: DateTime(2026, 11, 24, 23),
      now: now,
      dailySpend: 100,
    );
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklyRecapCard(
              recap: recap,
              onDoctorReport: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('weekly-recap-headline')), findsOneWidget);
    expect(find.text('CLEAN DAYS'), findsOneWidget);
    expect(find.text('6/7'), findsOneWidget);
    expect(find.text('SLIPS'), findsOneWidget);
    expect(find.text('BENZO ONLY'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-recap-next-step')),
      findsOneWidget,
    );
    expect(find.textContaining('112'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('weekly-recap-doctor-report')));
    expect(tapped, isTrue);
  });

  testWidgets('the section reads the live logs', (tester) async {
    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
    );
    await controller.load();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [recoveryProvider.overrideWith((ref) => controller)],
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: WeeklyRecapSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('weekly-recap-card')), findsOneWidget);
    expect(find.text('YOUR WEEK'), findsOneWidget);
  });
}
