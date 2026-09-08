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
      await tester.tap(find.text('ADD ANOTHER EVENT'));
      await tester.pump();
      store.failWrite = true;
      await tester.tap(find.text('SAVE 2 EVENTS'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save.'), findsOneWidget);
      expect(find.text('LOG RELAPSES'), findsOneWidget);
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        isEmpty,
      );
      store.failWrite = false;
      await tester.tap(find.text('SAVE 2 EVENTS'));
      await tester.pumpAndSettle();
      expect(find.text('LOG RELAPSES'), findsNothing);
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'small screen and enlarged text retain scrolling date controls and save actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpForm(tester, MemoryRecoveryStore(), scale: 1.5);
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('relapse-time-0')).hitTestable(),
        find.byType(ListView),
        const Offset(0, -150),
      );
      await tester.tap(find.byKey(const ValueKey('relapse-time-0')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('SAVE 1 EVENT'), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
