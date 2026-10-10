import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/app/no_lean_app.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recovery_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (call) async => call.method == 'drainActions' ? <String>[] : null,
        );
  });

  testWidgets('the RATE IT NOW notification action opens the recheck', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final controller = RecoveryController(
      store: MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': 12,
          // Keep the peak-hour wall and welcome-back notice out of the way.
          'riskWindowLock': false,
          'peakHourLock': false,
          'lastOpenedAt': DateTime.now().toIso8601String(),
          'events': [
            {
              'id': 'base',
              'type': 'recoveryStart',
              'timestamp': DateTime(2026, 1, 1).toIso8601String(),
              'metadata': {},
            },
            {
              'id': 'crave-1',
              'type': 'craving',
              'timestamp': DateTime.now()
                  .subtract(const Duration(minutes: 16))
                  .toIso8601String(),
              'metadata': {'intensity': 6, 'trigger': 'Habit', 'stress': 4},
            },
          ],
        }),
      ),
      relapseLock: FakeRelapseLock(),
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
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
    expect(find.text('RECHECK DUE'), findsOneWidget);

    NotificationService.instance.debugEmitAction('action_recheck');
    // The dashboard animates continuously; pump a bounded time.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('It was 6/10. How strong is it now?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recheck-save')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      controller.events
          .singleWhere((e) => e.type == RecoveryEventType.cravingCheck)
          .metadata['outcome'],
      'same',
    );
    expect(find.text('RECHECK DUE'), findsNothing);
  });
}
