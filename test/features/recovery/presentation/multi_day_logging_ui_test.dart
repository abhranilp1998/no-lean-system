import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/multi_day_log.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/presentation/relapse_log_sheet.dart';
import 'package:no_lean/features/timeline/presentation/widgets/event_tile.dart';

import '../../../support/recovery_fakes.dart';
import '../../../support/relapse_form.dart';

final fixedNow = DateTime(2026, 9, 19, 12);

Future<RecoveryController> pumpHost(
  WidgetTester tester,
  Widget Function(BuildContext context) body,
) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  final c = RecoveryController(
    store: MemoryRecoveryStore(),
    relapseLock: FakeRelapseLock(),
    now: () => fixedNow,
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
        home: Scaffold(body: Builder(builder: body)),
      ),
    ),
  );
  return c;
}

Widget openSheetButton(BuildContext context) => TextButton(
  onPressed: () => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => RelapseLogSheet(now: fixedNow),
  ),
  child: const Text('OPEN'),
);

Future<void> tapRevealed(WidgetTester tester, Finder finder) async {
  await revealInRelapseSheet(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> expectInSheet(WidgetTester tester, Finder finder) async {
  await revealInRelapseSheet(tester, finder);
  expect(finder, findsOneWidget);
}

List<RecoveryEvent> multiDayEvents(RecoveryController c) =>
    c.events.where((e) => e.metadata[multiDayMetadataKey] == true).toList();

void main() {
  testWidgets('pick several past days, confirm summary, save one per day', (
    tester,
  ) async {
    final c = await pumpHost(tester, openSheetButton);
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    await tapRevealed(
      tester,
      find.byKey(const ValueKey('open-multi-day-picker')),
    );
    expect(find.text('PICK THE DAYS'), findsOneWidget);
    expect(find.text('PICK AT LEAST ONE DAY'), findsOneWidget);

    // Future days cannot be picked.
    await tester.tap(find.byKey(const ValueKey('multi-day-cell-2026-09-20')));
    await tester.pump();
    expect(find.text('PICK AT LEAST ONE DAY'), findsOneWidget);

    for (final d in ['2026-09-14', '2026-09-16', '2026-09-17']) {
      await tester.tap(find.byKey(ValueKey('multi-day-cell-$d')));
      await tester.pump();
    }
    expect(find.text('USE 3 DAYS'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('multi-day-use')));
    await tester.pumpAndSettle();

    await expectInSheet(tester, find.text('LOG SEVERAL DAYS'));
    await expectInSheet(tester, find.byKey(const ValueKey('multi-day-card')));
    await expectInSheet(tester, find.text('3 DAYS PICKED'));
    await expectInSheet(tester, find.text('SAME FOR ALL 3 DAYS'));
    // Per-entry date pickers are replaced by the day list.
    expect(find.byKey(const ValueKey('relapse-date-0')), findsNothing);
    expect(find.text('ADD ANOTHER EVENT'), findsNothing);

    // Remove one day straight from the list.
    final slot = find.byKey(const ValueKey('multi-day-slot-2026-09-14'));
    await revealInRelapseSheet(tester, slot);
    await tester.tap(
      find.descendant(of: slot, matching: find.byTooltip('Remove this day')),
    );
    await tester.pumpAndSettle();
    await expectInSheet(tester, find.text('2 DAYS PICKED'));

    await tapRevealed(tester, find.text('LOG 2 ENTRIES'));
    expect(find.text('CHECK BEFORE SAVING'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('multi-day-confirm')),
        matching: find.textContaining('2 entries across 2 days'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Thu 17 Sep 2026 · 1 dose'), findsOneWidget);
    expect(
      find.textContaining('clean time will count from the latest'),
      findsOneWidget,
    );
    expect(multiDayEvents(c), isEmpty);

    await tester.tap(find.byKey(const ValueKey('confirm-multi-day')));
    await tester.pumpAndSettle();

    final saved = multiDayEvents(c);
    expect(saved.map((e) => e.timestamp), [
      DateTime(2026, 9, 16, 21),
      DateTime(2026, 9, 17, 21),
    ]);
    expect(saved.map((e) => e.id).toSet(), hasLength(2));
    expect(find.byType(RelapseLogSheet), findsNothing);
  });

  Future<void> openPickerWithDays(
    WidgetTester tester,
    List<String> days,
  ) async {
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tapRevealed(
      tester,
      find.byKey(const ValueKey('open-multi-day-picker')),
    );
    for (final d in days) {
      await tester.tap(find.byKey(ValueKey('multi-day-cell-$d')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('multi-day-use')));
    await tester.pumpAndSettle();
  }

  Finder textMatching(RegExp pattern) => find.byWidgetPredicate(
    (w) => w is Text && pattern.hasMatch(w.data ?? ''),
  );

  Future<List<String>> doseLabels(WidgetTester tester, String day) async {
    final row = find.byKey(ValueKey('multi-day-row-$day'));
    await revealInRelapseSheet(tester, row);
    return [
      for (final chip in tester.widgetList<InputChip>(
        find.descendant(of: row, matching: find.byType(InputChip)),
      ))
        (chip.label as Text).data!.replaceAll('\u202f', ' '),
    ];
  }

  testWidgets('several doses per day, one with its own amount and type', (
    tester,
  ) async {
    final c = await pumpHost(tester, openSheetButton);
    await openPickerWithDays(tester, ['2026-09-15', '2026-09-17']);
    await expectInSheet(tester, find.text('2 entries across 2 days'));

    // + DOSE: three hours after 9 PM would pass midnight, so the new dose
    // goes three hours before it (6 PM).
    await tapRevealed(
      tester,
      find.byKey(const ValueKey('multi-day-add-dose-2026-09-15')),
    );
    await expectInSheet(tester, find.text('3 entries across 2 days'));
    expect(
      find.byKey(const ValueKey('multi-day-slot-2026-09-15-1')),
      findsOneWidget,
    );
    expect(find.text('LOG 3 ENTRIES'), findsOneWidget);

    // Give the 6 PM dose of the 15th its own type and amount.
    await tapRevealed(
      tester,
      find.byKey(const ValueKey('multi-day-slot-2026-09-15')),
    );
    await tester.tap(find.byKey(const ValueKey('dose-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BENZO').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('dose-amount')), '2');
    await tester.tap(find.byKey(const ValueKey('dose-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('tablets').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dose-done')));
    await tester.pumpAndSettle();
    expect(
      textMatching(RegExp(r'6:00\s+PM · 2 tablets · BENZO')),
      findsOneWidget,
    );

    await tapRevealed(tester, find.text('LOG 3 ENTRIES'));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('multi-day-confirm')),
        matching: find.textContaining('3 entries across 2 days'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Tue 15 Sep 2026 · 2 doses'), findsOneWidget);
    expect(find.textContaining('Thu 17 Sep 2026 · 1 dose'), findsOneWidget);
    expect(find.textContaining('BENZO'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('confirm-multi-day')));
    await tester.pumpAndSettle();

    final saved = multiDayEvents(c);
    expect(saved, hasLength(3));
    expect(saved.map((e) => e.timestamp), [
      DateTime(2026, 9, 15, 18),
      DateTime(2026, 9, 15, 21),
      DateTime(2026, 9, 17, 21),
    ]);
    expect(saved.map((e) => e.id).toSet(), hasLength(3));
    expect(saved[0].metadata['relapseType'], 'benzo');
    expect(saved[0].metadata['unit'], 'tablet');
    expect(saved[1].metadata['relapseType'], 'fullLean');
    expect(saved[1].metadata['unit'], isNot('tablet'));
    // Lean timer follows the latest lean dose, not the earlier benzo one.
    expect(c.lastDose, DateTime(2026, 9, 17, 21));
  });

  testWidgets('doses per day stepper applies to all days; removing doses', (
    tester,
  ) async {
    final c = await pumpHost(tester, openSheetButton);
    await openPickerWithDays(tester, [
      '2026-09-14',
      '2026-09-15',
      '2026-09-16',
    ]);
    await tapRevealed(
      tester,
      find.byKey(const ValueKey('multi-day-doses-plus')),
    );
    await tapRevealed(
      tester,
      find.byKey(const ValueKey('multi-day-doses-plus')),
    );
    await expectInSheet(tester, find.text('9 entries across 3 days'));
    // Three doses a day: 9 AM, 3 PM, 9 PM.
    for (final day in ['2026-09-14', '2026-09-15', '2026-09-16']) {
      expect(await doseLabels(tester, day), ['9:00 AM', '3:00 PM', '9:00 PM']);
    }
    await tapRevealed(
      tester,
      find.byKey(const ValueKey('multi-day-doses-minus')),
    );
    await expectInSheet(tester, find.text('6 entries across 3 days'));
    for (final day in ['2026-09-14', '2026-09-15', '2026-09-16']) {
      expect(await doseLabels(tester, day), ['9:00 AM', '9:00 PM']);
    }

    // Remove the 9 AM dose of the 14th, then its last dose: the day goes.
    final first = find.byKey(const ValueKey('multi-day-slot-2026-09-14'));
    await revealInRelapseSheet(tester, first);
    await tester.tap(
      find.descendant(of: first, matching: find.byTooltip('Remove this dose')),
    );
    await tester.pumpAndSettle();
    await expectInSheet(tester, find.text('5 entries across 3 days'));
    final only = find.byKey(const ValueKey('multi-day-slot-2026-09-14'));
    await revealInRelapseSheet(tester, only);
    await tester.tap(
      find.descendant(of: only, matching: find.byTooltip('Remove this day')),
    );
    await tester.pumpAndSettle();
    await expectInSheet(tester, find.text('4 entries across 2 days'));
    expect(find.text('2 DAYS PICKED'), findsOneWidget);
    expect(multiDayEvents(c), isEmpty);
  });

  testWidgets('a dose cannot reuse another dose time on the same day', (
    tester,
  ) async {
    final c = await pumpHost(tester, openSheetButton);
    await openPickerWithDays(tester, ['2026-09-16']);
    await tapRevealed(
      tester,
      find.byKey(const ValueKey('multi-day-add-dose-2026-09-16')),
    );
    // The new dose is at 6 PM, before the 9 PM one. Moving the 9 PM dose
    // to 6 PM must be refused.
    expect(await doseLabels(tester, '2026-09-16'), ['6:00 PM', '9:00 PM']);
    await tapRevealed(
      tester,
      find.byKey(const ValueKey('multi-day-slot-2026-09-16-1')),
    );
    await tester.tap(find.byKey(const ValueKey('dose-time')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('relapse-hour')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SET TIME').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dose-done')));
    await tester.pumpAndSettle();
    expect(textMatching(RegExp(r'is already at 6:00\s+PM')), findsOneWidget);
    expect(multiDayEvents(c), isEmpty);
  });

  testWidgets('going back from the summary saves nothing', (tester) async {
    final c = await pumpHost(tester, openSheetButton);
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tapRevealed(
      tester,
      find.byKey(const ValueKey('open-multi-day-picker')),
    );
    await tester.tap(find.byKey(const ValueKey('multi-day-last-3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('multi-day-use')));
    await tester.pumpAndSettle();
    await tapRevealed(tester, find.text('LOG 3 ENTRIES'));
    await tester.tap(find.text('GO BACK'));
    await tester.pumpAndSettle();
    expect(multiDayEvents(c), isEmpty);
    expect(find.byType(RelapseLogSheet), findsOneWidget);

    // And the user can drop back to the single-event form.
    await tapRevealed(tester, find.byKey(const ValueKey('multi-day-leave')));
    await expectInSheet(tester, find.text('LOG RELAPSE'));
    await expectInSheet(tester, find.text('SAVE 1 EVENT'));
  });

  testWidgets('edit one saved day from history without touching the others', (
    tester,
  ) async {
    late RecoveryController controller;
    controller = await pumpHost(
      tester,
      (context) => Consumer(
        builder: (context, ref, _) {
          final events = ref
              .watch(recoveryProvider)
              .events
              .where((e) => e.metadata[multiDayMetadataKey] == true)
              .toList();
          return ListView(
            children: [for (final e in events) EventTile(event: e)],
          );
        },
      ),
    );
    final template = RelapseLogEntry(
      occurredAt: fixedNow,
      type: RelapseType.fullLean,
      note: 'Logging this later for days I missed.',
      attemptedSos: false,
    );
    await controller.recordRelapse(
      entries: [
        template.copyWith(occurredAt: DateTime(2026, 9, 15, 21)),
        template.copyWith(occurredAt: DateTime(2026, 9, 16, 21)),
      ],
      extraMetadata: const {multiDayMetadataKey: true},
    );
    await tester.pumpAndSettle();
    final before = multiDayEvents(controller);
    expect(find.text('LOGGED LATER'), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await expectInSheet(tester, find.text('EDIT ENTRY'));
    expect(
      find.descendant(
        of: find.byType(RelapseLogSheet),
        matching: find.text('Logging this later for days I missed.'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('open-multi-day-picker')), findsNothing);

    final note = find.byKey(const ValueKey('relapse-note-0'));
    await revealInRelapseSheet(tester, note);
    await tester.enterText(note, 'Only a small amount that night.');
    await tapRevealed(tester, find.text('SAVE CHANGES'));

    expect(find.byType(RelapseLogSheet), findsNothing);
    final after = {for (final e in multiDayEvents(controller)) e.id: e};
    expect(
      after[before[0].id]!.metadata['note'],
      'Only a small amount that night.',
    );
    expect(after[before[0].id]!.metadata['editedAt'], isNotNull);
    expect(after[before[1].id]!.metadata, before[1].metadata);
    expect(find.text('EDITED'), findsOneWidget);
  });
}
