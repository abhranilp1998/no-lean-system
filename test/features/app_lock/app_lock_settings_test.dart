import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/app_lock/application/app_lock_providers.dart';
import 'package:no_lean/features/app_lock/domain/locked_app.dart';
import 'package:no_lean/features/app_lock/presentation/app_lock_banner.dart';
import 'package:no_lean/features/app_lock/presentation/app_lock_settings_screen.dart';
import 'package:no_lean/features/app_lock/services/app_lock_gateway.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_app_lock_gateway.dart';
import '../../support/recovery_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('no_lean/widget_actions'),
          (_) async => <String>[],
        );
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget home,
    FakeAppLockGateway gateway,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
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
    container.read(appLockStatusProvider.notifier).state = await gateway
        .status();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildNoLeanTheme(), home: home),
      ),
    );
    await tester.pump();
    return container;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('the settings tile is live and opens the app lock screen', (
    tester,
  ) async {
    await pump(
      tester,
      const Scaffold(body: SettingsScreen()),
      FakeAppLockGateway(),
    );
    final tile = find.byKey(const ValueKey('settings-app-lock'));
    await tester.scrollUntilVisible(tile, 300);
    await tester.pumpAndSettle();
    expect(find.text('App lock (coming soon)'), findsNothing);
    expect(find.text('App lock'), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-lock-settings')), findsOneWidget);
  });

  testWidgets('enable, pick apps (protected ones disabled, payment apps '
      'suggested), schedule and budget', (tester) async {
    final gateway = FakeAppLockGateway(
      apps: const [
        InstalledAppInfo(packageName: 'com.example.chat', label: 'Chat'),
        InstalledAppInfo(packageName: 'com.phonepe.app', label: 'PhonePe'),
        InstalledAppInfo(
          packageName: 'com.google.android.dialer',
          label: 'Phone',
        ),
        InstalledAppInfo(
          packageName: 'com.vendor.home',
          label: 'Home',
          neverLockable: true,
        ),
      ],
    );
    final container = await pump(
      tester,
      const AppLockSettingsScreen(),
      gateway,
    );
    await tapKey(tester, 'app-lock-enabled');
    expect(container.read(recoveryProvider).appLockPolicy.enabled, isTrue);

    await tapKey(tester, 'app-lock-choose');
    expect(find.byKey(const ValueKey('app-picker')), findsOneWidget);
    final dialer = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('app-picker-com.google.android.dialer')),
    );
    expect(dialer.onChanged, isNull);
    final home = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('app-picker-com.vendor.home')),
    );
    expect(home.onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('app-picker-com.example.chat')));
    await tester.tap(find.byKey(const ValueKey('app-picker-com.phonepe.app')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('app-picker-done')));
    await tester.pumpAndSettle();

    var policy = container.read(recoveryProvider).appLockPolicy;
    expect(policy.enabledPackages, {'com.example.chat', 'com.phonepe.app'});
    expect(policy.appFor('com.phonepe.app')!.paymentApp, isTrue);
    expect(policy.appFor('com.example.chat')!.paymentApp, isFalse);

    await tapKey(tester, 'app-lock-schedule-always');
    expect(
      container.read(recoveryProvider).appLockPolicy.schedule,
      AppLockSchedule.always,
    );
    await tapKey(tester, 'app-lock-budget-down');
    expect(container.read(recoveryProvider).appLockPolicy.dailyUnlockBudget, 2);
    await tapKey(tester, 'app-lock-payment-com.example.chat');
    policy = container.read(recoveryProvider).appLockPolicy;
    expect(policy.appFor('com.example.chat')!.paymentApp, isTrue);
  });

  testWidgets('permission status with a grant button behind the disclosure', (
    tester,
  ) async {
    final gateway = FakeAppLockGateway(
      currentStatus: const AppLockStatus(supported: true),
    );
    await pump(tester, const AppLockSettingsScreen(), gateway);
    expect(find.text('GRANT USAGE ACCESS'), findsOneWidget);
    await tapKey(tester, 'app-lock-grant');
    expect(find.byKey(const ValueKey('app-lock-disclosure')), findsOneWidget);
    expect(gateway.usageRequests, 0, reason: 'nothing before consent');
    final cont = find.byKey(const ValueKey('app-lock-disclosure-continue'));
    await tester.scrollUntilVisible(cont, 200);
    await tester.pumpAndSettle();
    await tester.tap(cont);
    await tester.pumpAndSettle();
    expect(gateway.usageRequests, 1);

    gateway.currentStatus = const AppLockStatus(
      supported: true,
      usageAccess: true,
    );
    await tapKey(tester, 'app-lock-grant');
    expect(gateway.overlayRequests, 1);
  });

  test('fail-safe banner rules', () {
    const ok = AppLockStatus(
      supported: true,
      usageAccess: true,
      overlay: true,
      serviceRunning: true,
    );
    expect(appLockHealthMessage(armed: true, status: ok), isNull);
    expect(appLockHealthMessage(armed: false, status: null), isNull);
    expect(
      appLockHealthMessage(
        armed: true,
        status: const AppLockStatus.unsupported(),
      ),
      isNull,
    );
    expect(
      appLockHealthMessage(
        armed: false,
        status: const AppLockStatus(supported: true),
      ),
      isNull,
      reason: 'no banner while the lock is off',
    );
    expect(
      appLockHealthMessage(
        armed: true,
        status: const AppLockStatus(supported: true, overlay: true),
      ),
      contains('nothing is being locked'),
    );
    expect(
      appLockHealthMessage(
        armed: true,
        status: const AppLockStatus(supported: true, usageAccess: true),
      ),
      contains('Display over other apps'),
    );
    expect(
      appLockHealthMessage(
        armed: true,
        status: const AppLockStatus(
          supported: true,
          usageAccess: true,
          overlay: true,
        ),
      ),
      contains('Nothing is locked until it restarts'),
    );
  });

  testWidgets('settings shows Off as requested until native acknowledgement '
      'and fixes permissions without stacking settings routes', (tester) async {
    final gateway = FakeAppLockGateway(
      currentStatus: const AppLockStatus(
        supported: true,
        usageAccess: true,
        serviceRunning: true,
      ),
    );
    final container = await pump(
      tester,
      const AppLockSettingsScreen(),
      gateway,
    );
    container.read(appLockSyncPendingProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(
      find.text('Off requested // waiting for Android confirmation'),
      findsOneWidget,
    );
    expect(find.textContaining('APP LOCK TURNING OFF'), findsOneWidget);
    container.read(appLockSyncPendingProvider.notifier).state = false;
    container.read(appLockSyncFailureProvider.notifier).state =
        AppLockSyncFailure.deactivation;
    await tester.pumpAndSettle();
    expect(
      find.text('Off requested // Android has not confirmed stopping'),
      findsOneWidget,
    );
    expect(find.textContaining('APP LOCK UPDATE FAILED'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('app-lock-health-banner')),
        matching: find.textContaining('Display over other apps'),
      ),
      findsOneWidget,
    );
    final fix = find.byKey(const ValueKey('app-lock-health-fix'));
    await tester.ensureVisible(fix);
    await tester.tap(fix);
    await tester.pumpAndSettle();
    expect(gateway.overlayRequests, 1);
    expect(
      find.byKey(const ValueKey('app-lock-settings'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
    container.read(appLockSyncFailureProvider.notifier).state = null;
    await tester.pumpAndSettle();
    // Removing the warning shrinks the list above the toggle. Reveal it again
    // before checking the acknowledged Off presentation.
    final toggle = find.byKey(const ValueKey('app-lock-enabled'));
    await tester.scrollUntilVisible(toggle, -200);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('app-lock-enabled')),
        matching: find.text('Off'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('revoked usage access shows a re-grant banner', (tester) async {
    final gateway = FakeAppLockGateway(
      currentStatus: const AppLockStatus(supported: true, overlay: true),
    );
    final container = await pump(
      tester,
      const Scaffold(body: Column(children: [AppLockHealthBanner()])),
      gateway,
    );
    expect(find.byKey(const ValueKey('app-lock-health-banner')), findsNothing);
    await container
        .read(recoveryProvider)
        .updateAppLockPolicy(
          const AppLockPolicy(
            enabled: true,
            apps: [LockedApp(packageName: 'com.example.chat', label: 'Chat')],
          ),
        );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('app-lock-health-banner')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('app-lock-health-fix')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-lock-settings')), findsOneWidget);
  });
}
