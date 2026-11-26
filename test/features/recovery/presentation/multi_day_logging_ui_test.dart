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

    await tapRevealed(tester, find.text('LOG 2 DAYS'));
    expect(find.text('CHECK BEFORE SAVING'), findsOneWidget);
    expect(find.textContaining('Thu 17 Sep 2026 at 9:00'), findsOneWidget);
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
    await tapRevealed(tester, find.text('LOG 3 DAYS'));
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
