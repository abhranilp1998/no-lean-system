import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/presentation/relapse_log_sheet.dart';

import 'support/recovery_fakes.dart';

Future<RecoveryController> pumpForm(
  WidgetTester tester,
  MemoryRecoveryStore store, {
  double scale = 1,
}) async {
  final c = RecoveryController(store: store, relapseLock: FakeRelapseLock());
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRelapseLogSheet(context),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets(
    'failed batch keeps the form for retry and never shows saved success',
    (tester) async {
      final store = MemoryRecoveryStore();
      final c = await pumpForm(tester, store);
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      final addEvent = find.text('ADD ANOTHER EVENT');
      await tester.tap(addEvent);
      await tester.pump();
      await _enterRelapseNote(tester, 0, 'Bought after the work trigger hit.');
      await _enterRelapseNote(tester, 1, 'Returned to the same source later.');
      store.failWrite = true;
      await tester.tap(find.text('SAVE 2 EVENTS'));
      await tester.pumpAndSettle();
      expect(find.text('CONFIRM RELAPSE'), findsOneWidget);
      await tester.tap(find.text('CONFIRM RESET'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save.'), findsOneWidget);
      expect(find.byType(RelapseLogSheet), findsOneWidget);
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        isEmpty,
      );
      store.failWrite = false;
      await tester.tap(find.text('SAVE 2 EVENTS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CONFIRM RESET'));
      await tester.pumpAndSettle();
      expect(find.byType(RelapseLogSheet), findsNothing);
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        hasLength(2),
      );
    },
  );

  testWidgets('requires context and hard confirmation before resetting', (
    tester,
  ) async {
    final c = await pumpForm(tester, MemoryRecoveryStore());
    await tester.tap(find.text('SAVE 1 EVENT'));
    await tester.pump();
    expect(find.text('Use at least 12 characters.'), findsOneWidget);
    expect(find.text('CONFIRM RELAPSE'), findsNothing);
    expect(c.events.where((e) => e.type == RecoveryEventType.relapse), isEmpty);

    await _enterRelapseNote(tester, 0, 'After work pressure broke the plan.');
    await tester.tap(find.text('SAVE 1 EVENT'));
    await tester.pumpAndSettle();
    expect(find.text('CONFIRM RELAPSE'), findsOneWidget);
    await tester.tap(find.text('GO BACK'));
    await tester.pumpAndSettle();
    expect(find.byType(RelapseLogSheet), findsOneWidget);
    expect(c.events.where((e) => e.type == RecoveryEventType.relapse), isEmpty);
  });

  testWidgets('saves typed relapse metadata without changing the event model', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await pumpForm(tester, MemoryRecoveryStore());
    for (final tag in ['After Work', 'Office Stress']) {
      final chip = find.byKey(ValueKey('relapse-context-0-$tag'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
    }
    await _enterRelapseNote(
      tester,
      0,
      'I ignored the plan after leaving work.',
    );
    final quantity = find.byKey(const ValueKey('relapse-quantity-0'));
    await tester.ensureVisible(quantity);
    await tester.enterText(quantity, 'half a cup');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    final attemptedSos = find.byKey(const ValueKey('relapse-attempted-sos-0'));
    await tester.ensureVisible(attemptedSos);
    await tester.tap(attemptedSos);
    await tester.pump();
    await tester.tap(find.text('SAVE 1 EVENT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM RESET'));
    await tester.pumpAndSettle();

    final relapse = c.events.singleWhere(
      (event) => event.type == RecoveryEventType.relapse,
    );
    expect(relapse.metadata['relapseType'], 'fullLean');
    expect(relapse.metadata['attemptedSos'], isTrue);
    expect(relapse.metadata['quantity'], 'half a cup');
    expect(relapse.metadata['contextTags'], ['After Work', 'Office Stress']);
    expect(relapse.metadata['note'], 'I ignored the plan after leaving work.');
  });

  testWidgets(
    'small screen and enlarged text retain scrolling date controls and save actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpForm(tester, MemoryRecoveryStore(), scale: 1.5);
      final initialException = tester.takeException();
      if (initialException case final FlutterError error) {
        fail(error.toStringDeep());
      }
      expect(initialException, isNull);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('relapse-time-0')).hitTestable(),
        find.byType(ListView),
        const Offset(0, -150),
      );
      await tester.tap(find.byKey(const ValueKey('relapse-time-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('relapse-time-picker')), findsOneWidget);
      final pickerException = tester.takeException();
      if (pickerException case final FlutterError error) {
        fail('Time picker overflow:\n${error.toStringDeep()}');
      }
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('relapse-time-picker')),
          matching: find.text('CANCEL'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SAVE 1 EVENT'), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _enterRelapseNote(
  WidgetTester tester,
  int index,
  String value,
) async {
  final note = find.byKey(ValueKey('relapse-note-$index'));
  await tester.ensureVisible(note);
  await tester.enterText(note, value);
}
