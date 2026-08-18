// This is a basic Flutter widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:no_lean/main.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

void main() {
  testWidgets('NO LEAN launches into the recovery counter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: NoLeanApp()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('NO LEAN'), findsWidgets);
    expect(find.text('THE COUNTER'), findsOneWidget);
    expect(find.text('I WILL NOT BUY LEAN TODAY'), findsOneWidget);
  });

  testWidgets('Phase 1: PIN dialog opens, accepts input, and closes without crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: NoLeanApp()));
    await tester.pumpAndSettle();

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
  });

  testWidgets('Phase 3: Relapse Cooldown Screen locks the UI', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer();
    
    // Simulate an active cooldown
    final controller = container.read(recoveryProvider);
    controller.events.add(RecoveryEvent.create(type: RecoveryEventType.relapse));
    controller.relapseCooldownUntil = DateTime.now().add(const Duration(minutes: 15));
    
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NoLeanApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Cooldown Screen is visible
    expect(find.text('STREAK LOST.'), findsOneWidget);
    expect(find.text('SYSTEM LOCKED. READ YOUR REASONS.'), findsOneWidget);
    expect(find.text('EMERGENCY SOS'), findsOneWidget);

    // 2. Fast forward time to expire cooldown
    controller.relapseCooldownUntil = DateTime.now().subtract(const Duration(minutes: 1));
    
    // Pump to trigger the timer check
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // 3. Verify Debrief Screen appears
    expect(find.text('LOCK LIFTED.'), findsOneWidget);
    expect(find.text('What led to this relapse?'), findsOneWidget);

    // 4. Click a debrief option
    await tester.tap(find.text('CRAVING / URGE'));
    // Pump enough times to let the async clearRelapseCooldown finish
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // 5. Verify the app returns to the normal Shell
    expect(find.text('STREAK LOST.'), findsNothing);
    expect(find.text('LOCK LIFTED.'), findsNothing);
    expect(find.text('THE COUNTER'), findsOneWidget);
  });
}
