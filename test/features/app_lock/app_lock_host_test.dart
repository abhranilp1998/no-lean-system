import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/app_lock/application/app_lock_host.dart';
import 'package:no_lean/features/app_lock/application/app_lock_providers.dart';
import 'package:no_lean/features/app_lock/domain/locked_app.dart';
import 'package:no_lean/features/app_lock/presentation/app_lock_banner.dart';
import 'package:no_lean/features/app_lock/services/app_lock_gateway.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_app_lock_gateway.dart';
import '../../support/recovery_fakes.dart';

const _policy = AppLockPolicy(
  enabled: true,
  apps: [LockedApp(packageName: 'com.example.payment', label: 'Payment')],
  schedule: AppLockSchedule.off,
);

class _ControlledGateway extends FakeAppLockGateway {
  AppLockResult applyResult = const AppLockResult.unsupported('Start failed');
  AppLockResult disableResult = const AppLockResult.ok();
  bool throwOnApply = false;
  Completer<AppLockResult>? nextApply;
  int statusReads = 0;

  @override
  Future<AppLockResult> apply(Map<String, Object?> config) async {
    applied.add(config);
    if (throwOnApply) throw StateError('Private native exception data');
    final pending = nextApply;
    nextApply = null;
    if (pending != null) return pending.future;
    return applyResult;
  }

  @override
  Future<AppLockResult> disable() async {
    disables++;
    return disableResult;
  }

  @override
  Future<AppLockStatus> status() async {
    statusReads++;
    return currentStatus;
  }
}

Future<ProviderContainer> _pumpHost(
  WidgetTester tester,
  AppLockGateway gateway, {
  AppLockPolicy policy = _policy,
}) async {
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
  final recovery = container.read(recoveryProvider);
  await recovery.load();
  await recovery.updateAppLockPolicy(policy);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildNoLeanTheme(),
        home: const AppLockHost(
          child: Scaffold(body: Column(children: [AppLockHealthBanner()])),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('unsupported platforms stay quiet instead of reporting an '
      'Android update failure', (tester) async {
    final container = await _pumpHost(
      tester,
      const UnsupportedAppLockGateway(),
    );
    expect(container.read(appLockStatusProvider)!.supported, isFalse);
    expect(container.read(appLockSyncFailureProvider), isNull);
    expect(find.byKey(const ValueKey('app-lock-health-banner')), findsNothing);
  });

  testWidgets('failed activation retries on an unchanged-config state update', (
    tester,
  ) async {
    final gateway = _ControlledGateway();
    final container = await _pumpHost(tester, gateway);
    expect(gateway.applied, hasLength(1));

    gateway.applyResult = const AppLockResult.ok();
    await container.read(recoveryProvider).setSetting('highContrast', true);
    await tester.pumpAndSettle();
    expect(gateway.applied, hasLength(2));
  });

  testWidgets('failed activation is visible despite healthy native flags; '
      'retry clears it without changing history', (tester) async {
    final gateway = _ControlledGateway();
    final container = await _pumpHost(tester, gateway);
    final before = container.read(recoveryProvider).events.length;
    expect(container.read(appLockStatusProvider)!.serviceRunning, isTrue);
    expect(find.textContaining('APP LOCK NOT READY'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-lock-health-retry')), findsOneWidget);

    gateway.applyResult = const AppLockResult.ok();
    await tester.tap(find.byKey(const ValueKey('app-lock-health-retry')));
    await tester.pumpAndSettle();
    expect(gateway.applied, hasLength(2));
    expect(container.read(appLockSyncFailureProvider), isNull);
    expect(find.byKey(const ValueKey('app-lock-health-banner')), findsNothing);
    expect(container.read(recoveryProvider).events, hasLength(before));
  });

  testWidgets('acknowledged unchanged config is not pushed again', (
    tester,
  ) async {
    final gateway = _ControlledGateway()
      ..applyResult = const AppLockResult.ok();
    final container = await _pumpHost(tester, gateway);
    await container.read(recoveryProvider).setSetting('highContrast', true);
    await tester.pumpAndSettle();
    expect(gateway.applied, hasLength(1));
    expect(find.byKey(const ValueKey('app-lock-health-banner')), findsNothing);
  });

  testWidgets('failed replacement invalidates the older acknowledgement', (
    tester,
  ) async {
    final gateway = _ControlledGateway()
      ..applyResult = const AppLockResult.ok();
    final container = await _pumpHost(tester, gateway);
    final recovery = container.read(recoveryProvider);
    gateway.applyResult = const AppLockResult.unsupported('Replacement failed');
    await recovery.updateAppLockPolicy(
      _policy.copyWith(schedule: AppLockSchedule.always),
    );
    await tester.pumpAndSettle();
    expect(gateway.applied, hasLength(2));
    expect(find.textContaining('APP LOCK NOT READY'), findsOneWidget);

    gateway.applyResult = const AppLockResult.ok();
    await recovery.updateAppLockPolicy(_policy);
    await tester.pumpAndSettle();
    expect(gateway.applied, hasLength(3));
    expect(gateway.applied.last['schedule'], 'off');
    expect(container.read(appLockSyncFailureProvider), isNull);
  });

  testWidgets('throwing activation remains visible and retryable', (
    tester,
  ) async {
    final gateway = _ControlledGateway()..throwOnApply = true;
    await _pumpHost(tester, gateway);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('APP LOCK NOT READY'), findsOneWidget);
    expect(find.textContaining('Private native exception data'), findsNothing);

    gateway
      ..throwOnApply = false
      ..applyResult = const AppLockResult.ok();
    await tester.tap(find.byKey(const ValueKey('app-lock-health-retry')));
    await tester.pumpAndSettle();
    expect(gateway.applied, hasLength(2));
    expect(find.byKey(const ValueKey('app-lock-health-banner')), findsNothing);
  });

  testWidgets('failed disable stays visible with the policy off and retries', (
    tester,
  ) async {
    final gateway = _ControlledGateway()
      ..disableResult = const AppLockResult.unsupported('Stop failed');
    final container = await _pumpHost(
      tester,
      gateway,
      policy: _policy.copyWith(enabled: false),
    );
    expect(container.read(recoveryProvider).appLockPolicy.armed, isFalse);
    expect(gateway.disables, 1);
    expect(find.textContaining('APP LOCK UPDATE FAILED'), findsOneWidget);
    gateway.disableResult = const AppLockResult.ok();
    await tester.tap(find.byKey(const ValueKey('app-lock-health-retry')));
    await tester.pumpAndSettle();
    expect(gateway.disables, 2);
    expect(gateway.applied, isEmpty);
    expect(find.byKey(const ValueKey('app-lock-health-banner')), findsNothing);
  });

  testWidgets(
    'policy changes during apply are synchronized after it finishes',
    (tester) async {
      final pending = Completer<AppLockResult>();
      final gateway = _ControlledGateway()
        ..applyResult = const AppLockResult.ok()
        ..nextApply = pending;
      final container = await _pumpHost(tester, gateway);
      await container
          .read(recoveryProvider)
          .updateAppLockPolicy(
            _policy.copyWith(schedule: AppLockSchedule.always),
          );
      await tester.pump();
      expect(gateway.applied, hasLength(1));
      pending.complete(const AppLockResult.ok());
      await tester.pumpAndSettle();
      expect(gateway.applied, hasLength(2));
      expect(gateway.applied.last['schedule'], 'always');
      expect(container.read(appLockSyncFailureProvider), isNull);
    },
  );

  testWidgets('a queued explicit retry retains its force flag', (tester) async {
    final gateway = _ControlledGateway();
    await _pumpHost(tester, gateway);
    final pending = Completer<AppLockResult>();
    gateway
      ..applyResult = const AppLockResult.ok()
      ..nextApply = pending;
    await tester.tap(find.byKey(const ValueKey('app-lock-health-retry')));
    await tester.pumpAndSettle();
    expect(gateway.applied, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('app-lock-health-retry')));
    await tester.pump();
    pending.complete(const AppLockResult.ok());
    await tester.pumpAndSettle();
    expect(gateway.applied, hasLength(3));
  });

  testWidgets('resume retries failed activation with unchanged config', (
    tester,
  ) async {
    final gateway = _ControlledGateway();
    await _pumpHost(tester, gateway);
    gateway.applyResult = const AppLockResult.ok();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.applied, hasLength(2));
    expect(find.byKey(const ValueKey('app-lock-health-banner')), findsNothing);
  });

  testWidgets('success leaves existing permission warnings intact', (
    tester,
  ) async {
    final gateway = _ControlledGateway();
    await _pumpHost(tester, gateway);
    gateway
      ..applyResult = const AppLockResult.ok()
      ..currentStatus = const AppLockStatus(supported: true, overlay: true);
    await tester.tap(find.byKey(const ValueKey('app-lock-health-retry')));
    await tester.pumpAndSettle();
    expect(find.textContaining('APP LOCK NOT READY'), findsNothing);
    expect(find.textContaining('Usage access is off'), findsOneWidget);
  });

  testWidgets('disposing during a pending apply does not read dead providers', (
    tester,
  ) async {
    final pending = Completer<AppLockResult>();
    final gateway = _ControlledGateway()..nextApply = pending;
    await _pumpHost(tester, gateway);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(const AppLockResult.unsupported());
    await tester.pumpAndSettle();
    expect(gateway.statusReads, 0);
    expect(tester.takeException(), isNull);
  });
}
