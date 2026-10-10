import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/app/no_lean_app.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recovery_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
  });

  Future<RecoveryController> pumpApp(
    WidgetTester tester, {
    required DateTime now,
    String? pin,
  }) async {
    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await controller.load();
    if (pin != null) await controller.enableRelapseLock(pin);
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
    return controller;
  }

  Future<void> unlockWithPin(WidgetTester tester, String pin) async {
    await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, pin);
    await tester.tap(find.widgetWithText(FilledButton, 'UNLOCK'));
    await tester.pumpAndSettle();
  }

  final insideWindow = DateTime(2026, 10, 8, 18);
  final outsideWindow = DateTime(2026, 10, 8, 12);

  testWidgets('risk window with a PIN shows the wall; SOS and craving stay', (
    tester,
  ) async {
    await pumpApp(tester, now: insideWindow, pin: '2468');

    expect(find.byKey(const ValueKey('app-lock-screen')), findsOneWidget);
    expect(find.text('WINDOW LOCK ACTIVE'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('THE COUNTER'), findsNothing);
    expect(find.byKey(const ValueKey('app-lock-sos')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-lock-craving')), findsOneWidget);
  });

  testWidgets('a wrong PIN keeps the wall; the right PIN opens the shell', (
    tester,
  ) async {
    await pumpApp(tester, now: insideWindow, pin: '2468');

    await unlockWithPin(tester, '1111');
    expect(find.byKey(const ValueKey('app-lock-error')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await unlockWithPin(tester, '2468');
    expect(find.byKey(const ValueKey('app-lock-screen')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('THE COUNTER'), findsOneWidget);
  });

  testWidgets('no wall outside the window or without a PIN', (tester) async {
    await pumpApp(tester, now: outsideWindow, pin: '2468');
    expect(find.byKey(const ValueKey('app-lock-screen')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('no wall in the window when no PIN is set', (tester) async {
    await pumpApp(tester, now: insideWindow);
    expect(find.byKey(const ValueKey('app-lock-screen')), findsNothing);
  });

  testWidgets('logging a relapse re-locks the shell outside the window', (
    tester,
  ) async {
    final controller = await pumpApp(tester, now: outsideWindow, pin: '2468');
    expect(find.byType(NavigationBar), findsOneWidget);

    await controller.recordRelapse(pin: '2468', tryBiometrics: false);
    await tester.pump();
    await tester.pump();

    expect(find.text('LOCKED AFTER RELAPSE LOG'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await unlockWithPin(tester, '2468');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(controller.relockPending, isFalse);
  });

  testWidgets('Settings shows the window-lock toggle only with a PIN', (
    tester,
  ) async {
    await pumpApp(tester, now: outsideWindow, pin: '2468');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final toggle = find.text('Risk-window lock');
    await tester.dragUntilVisible(
      toggle,
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    expect(toggle, findsOneWidget);
  });
}
