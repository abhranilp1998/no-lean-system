// This is a basic Flutter widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:no_lean/main.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/widget_action_service.dart';
import 'package:flutter/services.dart';
import 'support/recovery_fakes.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
  });

  testWidgets('NO LEAN launches into the recovery counter', (
    WidgetTester tester,
  ) async {
    final container = await _pumpLoadedApp(tester);
    addTearDown(container.dispose);

    expect(find.text('NO LEAN'), findsWidgets);
    expect(find.text('THE COUNTER'), findsOneWidget);
    expect(find.text('I WILL NOT BUY LEAN TODAY'), findsOneWidget);
  });

  testWidgets(
    'Phase 1: PIN dialog opens, accepts input, and closes without crashing',
    (WidgetTester tester) async {
      final container = await _pumpLoadedApp(tester);
      addTearDown(container.dispose);

      // 1. Navigate to Settings Tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // 2. Scroll to and Tap Relapse Lock toggle
      final relapseLockFinder = find.text('Relapse lock');
      await tester.dragUntilVisible(
        relapseLockFinder,
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(relapseLockFinder.last); // The SwitchListTile title
      await tester.pumpAndSettle();

      // 3. Verify Dialog appears
      expect(find.text('SET RELAPSE LOCK PIN'), findsOneWidget);

      // 4. Enter PIN
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      await tester.enterText(textFields.first, '1234');
      await tester.enterText(textFields.last, '1234');
      await tester.pumpAndSettle();

      // 5. Submit Dialog
      await tester.tap(find.text('ENABLE SECURE LOCK'));
      await tester.pumpAndSettle();

      // 6. Verify Dialog closed gracefully
      expect(find.text('SET RELAPSE LOCK PIN'), findsNothing);
    },
  );

  testWidgets(
    'Cooldown preserves navigation, repeat logging and optional reflection',
    (tester) async {
      final container = await _pumpLoadedApp(tester);
      addTearDown(container.dispose);
      final controller = container.read(recoveryProvider);
      await controller.recordRelapse();
      await tester.pump();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('LOG MORE EVENTS'), findsOneWidget);
      await tester.tap(find.text('LOG MORE EVENTS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ADD ANOTHER EVENT'));
      await tester.pump();
      expect(find.byKey(const ValueKey('relapse-date-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('relapse-time-1')), findsOneWidget);
      await tester.tap(find.text('SAVE 2 EVENTS'));
      await tester.pumpAndSettle();
      expect(
        controller.events.where((e) => e.type == RecoveryEventType.relapse),
        hasLength(3),
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Tune the override.'), findsOneWidget);
      await tester.tap(find.text('Counter'));
      await tester.pumpAndSettle();
      controller.relapseCooldownUntil = DateTime.now().subtract(
        const Duration(minutes: 1),
      );
      await tester.tap(find.text('OPEN RESET SUPPORT'));
      await tester.pumpAndSettle();
      expect(find.text('READY TO REFLECT?'), findsOneWidget);
      await tester.tap(find.text('CRAVING / URGE'));
      await tester.pumpAndSettle();
      expect(find.text('THE COUNTER'), findsOneWidget);
      expect(controller.relapseCooldownUntil, isNull);
    },
  );

  testWidgets(
    'Startup read failure shows retry and recovers without reinstall',
    (tester) async {
      final store = MemoryRecoveryStore()..failRead = true;
      final controller = RecoveryController(store: store);
      await controller.load();
      final container = ProviderContainer(
        overrides: [recoveryProvider.overrideWith((ref) => controller)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const NoLeanApp(),
        ),
      );
      expect(find.text('RETRY'), findsOneWidget);
      expect(find.text('EXPORT PRESERVED DATA'), findsOneWidget);
      store.failRead = false;
      await tester.tap(find.text('RETRY'));
      await tester.pumpAndSettle();
      expect(find.text('THE COUNTER'), findsOneWidget);
    },
  );

  testWidgets(
    'Widget cold and warm relapse actions open the dated batch form during cooldown',
    (tester) async {
      final pending = <String>['relapse'];
      const channel = MethodChannel('no_lean/widget_actions');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'drainActions') {
          final actions = List<String>.of(pending);
          pending.clear();
          return actions;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final container = await _pumpLoadedApp(tester);
      addTearDown(container.dispose);
      await tester.pumpAndSettle();
      expect(find.text('LOG RELAPSES'), findsOneWidget);
      await tester.tap(find.text('SAVE 1 EVENT'));
      await tester.pumpAndSettle();
      pending.add('relapse');
      await WidgetActionService.instance.initialize();
      await tester.pumpAndSettle();
      expect(find.text('LOG RELAPSES'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('relapse-date-0')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('relapse-time-0')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(recoveryProvider)
            .events
            .where((e) => e.type == RecoveryEventType.relapse),
        hasLength(1),
      );
    },
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 50,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the requested widget.');
}

Future<ProviderContainer> _pumpLoadedApp(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      recoveryProvider.overrideWith(
        (ref) => RecoveryController(
          store: MemoryRecoveryStore(),
          relapseLock: FakeRelapseLock(),
        )..load(),
      ),
    ],
  );
  await container.read(recoveryProvider).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const NoLeanApp()),
  );
  await _pumpUntil(tester, find.text('THE COUNTER'));
  await tester.pumpAndSettle();
  return container;
}
