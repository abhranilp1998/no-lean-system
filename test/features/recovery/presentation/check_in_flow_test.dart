import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/emergency/presentation/emergency_screen.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/daily_check_in.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/presentation/check_in_slip_details.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';
import 'package:no_lean/features/settings/presentation/settings_screen.dart';
import 'package:no_lean/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/check_in_fakes.dart';
import '../../../support/recovery_fakes.dart';

/// The full app has endless animations, so pumpAndSettle never ends.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  // Recent baseline: no milestone celebration route to cover the dialogs.
  final baseline = DateTime.now().subtract(const Duration(hours: 6));
  final tapAt = DateTime.now().subtract(const Duration(hours: 2));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
  });

  Future<(ProviderContainer, MemoryCheckInInbox)> boot(
    WidgetTester tester, {
    Widget? home,
    List<CheckInEntry> entries = const [],
    Map<String, Object?> extra = const {},
  }) async {
    final inbox = MemoryCheckInInbox()..pending.addAll(entries);
    final real = DateTime.now();
    final minute = real.hour * 60 + real.minute;
    final controller = RecoveryController(
      store: MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': 17,
          'events': [
            RecoveryEvent.create(
              type: RecoveryEventType.recoveryStart,
              timestamp: baseline,
            ).toJson(),
          ],
          'zones': [],
          // Keep the peak-hour gate and the window lock out of these flows.
          'riskWindow': RiskWindow(
            startMinutes: (minute + 180) % RiskWindow.minutesPerDay,
            endMinutes: (minute + 240) % RiskWindow.minutesPerDay,
          ).toJson(),
          ...extra,
        }),
      ),
      relapseLock: FakeRelapseLock(),
      checkInInbox: inbox,
    );
    await controller.load();
    final container = ProviderContainer(
      overrides: [recoveryProvider.overrideWith((ref) => controller)],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child:
            home ??
            MaterialApp(
              theme: buildNoLeanTheme(),
              home: const Scaffold(body: SettingsScreen()),
            ),
      ),
    );
    await tester.pump();
    return (container, inbox);
  }

  testWidgets(
    'settings: daily check-in is off by default and shows its time when on',
    (tester) async {
      final (container, _) = await boot(tester);
      final toggle = find.byKey(const ValueKey('settings-daily-check-in'));
      await tester.scrollUntilVisible(toggle, 300);
      await tester.pumpAndSettle();
      expect(container.read(recoveryProvider).dailyCheckIn, isFalse);
      expect(
        find.byKey(const ValueKey('settings-check-in-time')),
        findsNothing,
      );
      expect(
        find.textContaining('one-tap Okay / Struggling / Used'),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(container.read(recoveryProvider).dailyCheckIn, isTrue);
      expect(
        find.byKey(const ValueKey('settings-check-in-time')),
        findsOneWidget,
      );
      expect(find.textContaining('Every day at 20:00'), findsOneWidget);
    },
  );

  testWidgets(
    'settings: a check-in time inside quiet hours says it will not be sent',
    (tester) async {
      await boot(
        tester,
        extra: {
          'dailyCheckIn': true,
          'dailyCheckInMinutes': 23 * 60,
          'quietHoursEnabled': true,
          'quietHours': {'startMinutes': 22 * 60, 'endMinutes': 7 * 60},
        },
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-daily-check-in')),
        300,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('inside quiet hours'), findsOneWidget);
    },
  );

  testWidgets(
    'details prompt: benzo-only saves, recalculates and the lean timer returns',
    (tester) async {
      final (container, _) = await boot(tester);
      final c = container.read(recoveryProvider);
      await c.recordCheckInUsed(at: tapAt);
      expect(c.lastDose.difference(tapAt).inSeconds.abs() < 2, isTrue);
      final slip = c.slipsNeedingDetails.single;
      late BuildContext context;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildNoLeanTheme(),
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  context = ctx;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      unawaited(showSlipDetailsPrompt(context, slip));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slip-details-prompt')), findsOneWidget);
      expect(find.textContaining('it counts as lean'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('slip-type-benzo')));
      await tester.pump();
      expect(
        find.textContaining('lean clean time keeps counting'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('slip-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('slip-details-prompt')), findsNothing);
      expect(c.slipsNeedingDetails, isEmpty);
      expect(c.lastDose, baseline);
    },
  );

  testWidgets('details prompt: keep as lean, later, and wrong tap', (
    tester,
  ) async {
    final (container, _) = await boot(tester);
    final c = container.read(recoveryProvider);
    await c.recordCheckInUsed(at: tapAt);
    final slip = c.slipsNeedingDetails.single;
    late BuildContext context;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                context = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    // Save is inert until a type is chosen.
    unawaited(showSlipDetailsPrompt(context, slip));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slip-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('slip-details-prompt')), findsOneWidget);
    // Later closes and leaves it pending for the next open.
    await tester.tap(find.byKey(const ValueKey('slip-later')));
    await tester.pumpAndSettle();
    expect(c.slipsNeedingDetails, hasLength(1));

    unawaited(showSlipDetailsPrompt(context, slip));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slip-keep')));
    await tester.pumpAndSettle();
    expect(c.slipsNeedingDetails, isEmpty);
    expect(c.lastDose.difference(tapAt).inSeconds.abs() < 2, isTrue);

    await c.recordCheckInUsed(
      at: tapAt.subtract(const Duration(hours: 5)),
      entryId: 'second',
    );
    final second = c.slipsNeedingDetails.single;
    unawaited(showSlipDetailsPrompt(context, second));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slip-remove')));
    await tester.pumpAndSettle();
    expect(c.events.any((e) => e.id == second.id), isFalse);
  });

  testWidgets('app open: a background Used asks for details; Okay does not', (
    tester,
  ) async {
    final (container, _) = await boot(
      tester,
      home: const NoLeanApp(),
      entries: [
        CheckInEntry(
          id: 'ok',
          answer: CheckInAnswer.okay,
          at: tapAt.subtract(const Duration(hours: 20)),
        ),
        CheckInEntry(id: 'used', answer: CheckInAnswer.used, at: tapAt),
      ],
    );
    await settle(tester);
    final c = container.read(recoveryProvider);
    expect(c.slipsNeedingDetails, hasLength(1));
    expect(find.byKey(const ValueKey('slip-details-prompt')), findsOneWidget);
    expect(
      c.events.where((e) => e.type == RecoveryEventType.cleanCheckIn),
      hasLength(1),
    );
    await tester.tap(find.byKey(const ValueKey('slip-later')));
    await settle(tester);
    // Asked once per open: LATER does not nag again in the same session.
    expect(find.byKey(const ValueKey('slip-details-prompt')), findsNothing);
    expect(c.slipsNeedingDetails, hasLength(1));
  });

  testWidgets('Struggling opens the SOS urge tools', (tester) async {
    await boot(tester, home: const NoLeanApp());
    await settle(tester);
    expect(find.byType(EmergencyScreen), findsNothing);
    NotificationService.instance.debugEmitAction(checkInStrugglingAction);
    await settle(tester);
    expect(find.byType(EmergencyScreen), findsOneWidget);
  });

  testWidgets(
    'Used from the shade with the relapse lock off logs one tap-time slip',
    (tester) async {
      final (container, _) = await boot(tester, home: const NoLeanApp());
      await settle(tester);
      NotificationService.instance.debugEmitAction(checkInUsedOpenAction);
      await settle(tester);
      final c = container.read(recoveryProvider);
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        hasLength(1),
      );
      expect(c.slipsNeedingDetails, hasLength(1));
      expect(find.byKey(const ValueKey('slip-details-prompt')), findsOneWidget);
    },
  );
}
