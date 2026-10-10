import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/app/shell.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/app_lock/application/app_lock_host.dart';
import 'package:no_lean/features/app_lock/application/app_lock_providers.dart';
import 'package:no_lean/features/app_lock/domain/locked_app.dart';
import 'package:no_lean/features/app_lock/presentation/app_block_screen.dart';
import 'package:no_lean/features/app_lock/services/app_lock_gateway.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_app_lock_gateway.dart';
import '../../support/recovery_fakes.dart';

void main() {
  const chat = LockedApp(packageName: 'com.example.chat', label: 'Chat');
  const pay = LockedApp(
    packageName: 'com.phonepe.app',
    label: 'PhonePe',
    paymentApp: true,
  );
  const policy = AppLockPolicy(
    enabled: true,
    apps: [chat, pay],
    schedule: AppLockSchedule.always,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
  });

  Future<(ProviderContainer, FakeAppLockGateway, FakeRelapseLock)> pump(
    WidgetTester tester, {
    AppBlockRequest request = const AppBlockRequest(
      packageName: 'com.example.chat',
      label: 'Chat',
      zoneName: 'Corner',
      cause: 'zone',
    ),
    int budget = 3,
    String? pin,
    List<Uri>? dialed,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final gateway = FakeAppLockGateway();
    final lock = FakeRelapseLock();
    final container = ProviderContainer(
      overrides: [
        appLockGatewayProvider.overrideWithValue(gateway),
        recoveryProvider.overrideWith(
          (ref) => RecoveryController(
            store: MemoryRecoveryStore(),
            relapseLock: lock,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final recovery = container.read(recoveryProvider);
    await recovery.load();
    await recovery.updateAppLockPolicy(
      policy.copyWith(dailyUnlockBudget: budget),
    );
    if (pin != null) await recovery.enableRelapseLock(pin);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppBlockScreen(
                        request: request,
                        dialer: (uri) async {
                          dialed?.add(uri);
                          return true;
                        },
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (container, gateway, lock);
  }

  Iterable<RecoveryEvent> unlocks(ProviderContainer c) => c
      .read(recoveryProvider)
      .events
      .where((e) => e.type == RecoveryEventType.appUnlock);

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('SOS, Call 112 and Go home are always on screen', (tester) async {
    final dialed = <Uri>[];
    final (_, gateway, _) = await pump(tester, dialed: dialed);
    expect(find.text('APP LOCKED // CHAT'), findsOneWidget);
    expect(find.textContaining('You are inside Corner.'), findsOneWidget);
    for (final stage in ['locked', 'reason', 'waiting']) {
      expect(find.byKey(const ValueKey('app-block-sos')), findsOneWidget);
      expect(find.byKey(const ValueKey('app-block-call-112')), findsOneWidget);
      expect(find.byKey(const ValueKey('app-block-home')), findsOneWidget);
      if (stage == 'locked') await tapKey(tester, 'app-block-need');
      if (stage == 'reason') await tapKey(tester, 'app-block-reason-work');
    }
    await tapKey(tester, 'app-block-call-112');
    expect(dialed.single.toString(), 'tel:112');
    await tapKey(tester, 'app-block-home');
    await tester.pumpAndSettle();
    expect(gateway.homes, 1);
    expect(find.byKey(const ValueKey('app-block-screen')), findsNothing);
  });

  testWidgets('Back always goes home: the user is never trapped', (
    tester,
  ) async {
    final (_, gateway, _) = await pump(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(gateway.homes, 1);
    expect(find.byKey(const ValueKey('app-block-screen')), findsNothing);
  });

  testWidgets('I need this app: reason, 30 s mindful wait with own reasons, '
      'then that app only for 5 minutes, logged', (tester) async {
    final (container, gateway, _) = await pump(tester);
    expect(find.textContaining('3 of 3 unlocks left today'), findsOneWidget);
    await tapKey(tester, 'app-block-need');
    for (final reason in ['payment', 'work', 'navigation', 'urgent', 'other']) {
      expect(find.byKey(ValueKey('app-block-reason-$reason')), findsOneWidget);
    }
    await tapKey(tester, 'app-block-reason-work');
    expect(find.text('BREATHE // 30 s'), findsOneWidget);
    final reasons = container.read(recoveryProvider).reasons;
    expect(find.text('• ${reasons.first}'), findsOneWidget);
    await tester.pump(const Duration(seconds: 29));
    expect(find.byKey(const ValueKey('app-block-open')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('app-block-open')), findsOneWidget);
    expect(find.text('OPEN CHAT FOR 5 MIN'), findsOneWidget);
    await tapKey(tester, 'app-block-open');
    await tester.pumpAndSettle();
    expect(gateway.grants.single.$1, 'com.example.chat');
    expect(gateway.grants.single.$2, const Duration(minutes: 5));
    final event = unlocks(container).single;
    expect(event.metadata['reason'], 'work');
    expect(event.metadata['method'], 'budget');
    expect(event.metadata['zoneName'], 'Corner');
    expect(event.metadata['appLabel'], 'Chat');
    expect(container.read(recoveryProvider).appUnlocksLeftToday, 2);
    expect(find.byKey(const ValueKey('app-block-screen')), findsNothing);
  });

  testWidgets('cancelling the wait grants nothing', (tester) async {
    final (container, gateway, _) = await pump(tester);
    await tapKey(tester, 'app-block-need');
    await tapKey(tester, 'app-block-reason-other');
    await tester.pump(const Duration(seconds: 5));
    await tapKey(tester, 'app-block-wait-cancel');
    await tester.pump(const Duration(seconds: 40));
    expect(find.byKey(const ValueKey('app-block-open')), findsNothing);
    expect(gateway.grants, isEmpty);
    expect(unlocks(container), isEmpty);
  });

  testWidgets('payment apps take the 10 s quick path', (tester) async {
    final (container, gateway, _) = await pump(
      tester,
      request: const AppBlockRequest(
        packageName: 'com.phonepe.app',
        label: 'PhonePe',
        zoneName: 'Corner',
        cause: 'zone',
      ),
    );
    expect(find.textContaining('Payment app: 10 s wait.'), findsOneWidget);
    await tapKey(tester, 'app-block-need');
    await tapKey(tester, 'app-block-reason-payment');
    expect(find.text('BREATHE // 10 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tapKey(tester, 'app-block-open');
    await tester.pumpAndSettle();
    expect(gateway.grants.single.$1, 'com.phonepe.app');
    final event = unlocks(container).single;
    expect(event.metadata['paymentApp'], isTrue);
    expect(event.metadata['waitSeconds'], 10);
  });

  testWidgets('budget used up: the existing PIN opens it', (tester) async {
    final (container, gateway, _) = await pump(tester, budget: 0, pin: '1234');
    expect(find.textContaining('Your PIN opens it'), findsOneWidget);
    await tapKey(tester, 'app-block-need');
    await tapKey(tester, 'app-block-reason-urgent');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('UNLOCK'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'app-block-open');
    await tester.pumpAndSettle();
    expect(gateway.grants, hasLength(1));
    expect(unlocks(container).single.metadata['method'], 'pin');
  });

  testWidgets('PIN lockout is never a dead end: long wait instead', (
    tester,
  ) async {
    final (container, gateway, lock) = await pump(
      tester,
      budget: 0,
      pin: '1234',
    );
    lock.lockedOut = true;
    await tapKey(tester, 'app-block-need');
    await tapKey(tester, 'app-block-reason-payment');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('UNLOCK'));
    await tester.pump();
    await tester.pump();
    expect(find.text('BREATHE // 120 s'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-block-error')), findsOneWidget);
    await tester.pump(const Duration(seconds: 120));
    await tapKey(tester, 'app-block-open');
    await tester.pumpAndSettle();
    expect(gateway.grants, hasLength(1));
    expect(unlocks(container).single.metadata['method'], 'longWait');
  });

  testWidgets('no PIN and no budget: a long wait still opens it', (
    tester,
  ) async {
    final (container, _, _) = await pump(tester, budget: 0);
    expect(find.textContaining('A longer wait still opens it'), findsOneWidget);
    await tapKey(tester, 'app-block-need');
    await tapKey(tester, 'app-block-reason-navigation');
    expect(find.text('BREATHE // 120 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 120));
    await tapKey(tester, 'app-block-open');
    await tester.pumpAndSettle();
    expect(unlocks(container).single.metadata['method'], 'longWait');
  });

  testWidgets('the host pushes config, opens the block screen for a locked '
      'app and ignores stale requests', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final gateway = FakeAppLockGateway();
    final container = ProviderContainer(
      overrides: [
        appLockGatewayProvider.overrideWithValue(gateway),
        recoveryProvider.overrideWith(
          (ref) => RecoveryController(
            store: MemoryRecoveryStore(),
            relapseLock: FakeRelapseLock(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(recoveryProvider).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: const AppLockHost(child: Scaffold(body: Text('home'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.disables, 1, reason: 'lock off -> native disabled');
    await container.read(recoveryProvider).updateAppLockPolicy(policy);
    await tester.pumpAndSettle();
    expect(gateway.applied.last['enabled'], isTrue);
    expect(gateway.applied.last['packages'], contains('com.example.chat'));
    expect(container.read(appLockStatusProvider)?.serviceRunning, isTrue);

    gateway.pushBlock(
      const AppBlockRequest(packageName: 'com.not.locked', label: 'Other'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-block-screen')), findsNothing);

    gateway.pushBlock(
      const AppBlockRequest(packageName: 'com.example.chat', label: 'Chat'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-block-screen')), findsOneWidget);
    expect(find.textContaining('Always lock is on'), findsOneWidget);
  });

  testWidgets('the zone alert screen is untouched by the app lock', (
    tester,
  ) async {
    // Shell still builds with the banner slot and no app-lock UI when off.
    final container = ProviderContainer(
      overrides: [
        appLockGatewayProvider.overrideWithValue(FakeAppLockGateway()),
        recoveryProvider.overrideWith(
          (ref) => RecoveryController(
            store: MemoryRecoveryStore(),
            relapseLock: FakeRelapseLock(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(recoveryProvider).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildNoLeanTheme(), home: const Shell()),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('app-lock-health-banner')), findsNothing);
  });
}
