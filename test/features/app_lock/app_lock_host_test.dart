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
  bool throwOnDisable = false;
  Completer<AppLockResult>? nextApply;
  Completer<AppLockResult>? nextDisable;
  Completer<AppLockStatus>? nextStatus;
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
    if (throwOnDisable) throw StateError('Private stop exception');
    final pending = nextDisable;
    nextDisable = null;
    if (pending != null) return pending.future;
    return disableResult;
  }

  @override
  Future<AppLockStatus> status() async {
    statusReads++;
    final pending = nextStatus;
    nextStatus = null;
    if (pending != null) return pending.future;
    return currentStatus;
  }
}

class _PendingSaveStore extends MemoryRecoveryStore {
  Completer<void>? nextWrite;
  bool waitingForWrite = false;

  @override
  Future<void> write(String next) async {
    final pending = nextWrite;
    nextWrite = null;
    if (pending != null) {
      waitingForWrite = true;
      try {
        await pending.future;
      } finally {
        waitingForWrite = false;
      }
    }
    await super.write(next);
  }
}

Future<ProviderContainer> _pumpHost(
  WidgetTester tester,
  AppLockGateway gateway, {
  AppLockPolicy policy = _policy,
  MemoryRecoveryStore? store,
}) async {
  final container = ProviderContainer(
    overrides: [
      appLockGatewayProvider.overrideWithValue(gateway),
      recoveryProvider.overrideWith(
        (ref) => RecoveryController(
          store: store ?? MemoryRecoveryStore(),
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

  testWidgets('saved-Off startup with no selected apps keeps native-request '
      'essential actions after a failed stop', (tester) async {
    final gateway = _ControlledGateway()
      ..disableResult = const AppLockResult.unsupported('Stop failed')
      ..pending.add(
        const AppBlockRequest(packageName: 'com.old.payment', label: 'Old app'),
      );
    final container = await _pumpHost(
      tester,
      gateway,
      policy: const AppLockPolicy(),
    );
    expect(container.read(recoveryProvider).appLockPolicy.apps, isEmpty);
    expect(find.byKey(const ValueKey('app-block-screen')), findsOneWidget);
    expect(
      find.textContaining('Android has not confirmed turning app lock off'),
      findsOneWidget,
    );
    for (final action in ['sos', 'call-112', 'home']) {
      expect(find.byKey(ValueKey('app-block-$action')), findsOneWidget);
    }
    final call = tester.widget<FilledButton>(
      find.byKey(const ValueKey('app-block-call-112')),
    );
    expect(
      call.onPressed,
      isNotNull,
      reason: 'never dial a real number in tests',
    );
    final home = find.byKey(const ValueKey('app-block-home'));
    await tester.ensureVisible(home);
    await tester.tap(home);
    await tester.pumpAndSettle();
    expect(gateway.homes, 1);
    expect(find.textContaining('APP LOCK UPDATE FAILED'), findsOneWidget);
    expect(gateway.grants, isEmpty);

    gateway.disableResult = const AppLockResult.ok();
    await tester.tap(find.byKey(const ValueKey('app-lock-health-retry')));
    await tester.pumpAndSettle();
    expect(container.read(appLockNativeStateUnconfirmedProvider), isFalse);
    gateway.pushBlock(
      const AppBlockRequest(packageName: 'com.old.payment', label: 'Old app'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-block-screen')), findsNothing);
  });

  testWidgets('pending disable keeps native requests reachable until the '
      'accepted stop dismisses the stale prompt', (tester) async {
    final stop = Completer<AppLockResult>();
    final gateway = _ControlledGateway()
      ..applyResult = const AppLockResult.ok();
    final container = await _pumpHost(tester, gateway);
    gateway.nextDisable = stop;
    await container
        .read(recoveryProvider)
        .updateAppLockPolicy(const AppLockPolicy());
    await tester.pumpAndSettle();
    expect(container.read(appLockSyncPendingProvider), isTrue);
    expect(find.textContaining('APP LOCK TURNING OFF'), findsOneWidget);
    gateway.pushBlock(
      const AppBlockRequest(packageName: 'com.old.payment', label: 'Old app'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-block-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-block-sos')), findsOneWidget);
    stop.complete(const AppLockResult.ok());
    await tester.pumpAndSettle();
    expect(container.read(appLockNativeStateUnconfirmedProvider), isFalse);
    expect(find.byKey(const ValueKey('app-block-screen')), findsNothing);
    expect(gateway.grants, isEmpty);
  });

  testWidgets('an old apply acknowledgement cannot settle a newer Off request '
      'while native status is in flight', (tester) async {
    final apply = Completer<AppLockResult>();
    final status = Completer<AppLockStatus>();
    final stop = Completer<AppLockResult>();
    final gateway = _ControlledGateway()..nextApply = apply;
    final container = await _pumpHost(tester, gateway);
    await container
        .read(recoveryProvider)
        .updateAppLockPolicy(const AppLockPolicy());
    await tester.pump();
    gateway
      ..nextStatus = status
      ..nextDisable = stop;
    apply.complete(const AppLockResult.ok());
    await tester.pump();
    expect(container.read(appLockSyncPendingProvider), isTrue);
    gateway.pushBlock(
      const AppBlockRequest(packageName: 'com.old.payment', label: 'Old app'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-block-screen')), findsOneWidget);
    status.complete(gateway.currentStatus);
    await tester.pumpAndSettle();
    expect(gateway.disables, 1);
    expect(container.read(appLockSyncPendingProvider), isTrue);
    stop.complete(const AppLockResult.ok());
    await tester.pumpAndSettle();
    expect(container.read(appLockNativeStateUnconfirmedProvider), isFalse);
    expect(find.byKey(const ValueKey('app-block-screen')), findsNothing);
  });

  testWidgets('confirmed disable removes only the block route while SOS '
      'remains open and Back returns home', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final stop = Completer<AppLockResult>();
    final gateway = _ControlledGateway()
      ..nextDisable = stop
      ..pending.add(
        const AppBlockRequest(packageName: 'com.old.payment', label: 'Old app'),
      );
    final container = await _pumpHost(
      tester,
      gateway,
      policy: const AppLockPolicy(),
    );
    final sos = find.byKey(const ValueKey('app-block-sos'));
    await tester.ensureVisible(sos);
    await tester.pumpAndSettle();
    await tester.tap(sos);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sos-screen')), findsOneWidget);
    stop.complete(const AppLockResult.ok());
    await tester.pumpAndSettle();
    expect(container.read(appLockNativeStateUnconfirmedProvider), isFalse);
    expect(find.byKey(const ValueKey('sos-screen')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('app-block-screen'), skipOffstage: false),
      findsNothing,
    );
    // Respect SOS's existing initial breathing interval before trying Back.
    await tester.pump(const Duration(seconds: 15));
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sos-screen')), findsNothing);
    expect(find.byKey(const ValueKey('app-lock-health-banner')), findsNothing);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
    );
    expect(gateway.grants, isEmpty);
  });

  testWidgets('accepted stop during an unlock-record save does not read a '
      'disposed ref or grant a stale unlock', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final stop = Completer<AppLockResult>();
    final save = Completer<void>();
    final store = _PendingSaveStore();
    final gateway = _ControlledGateway()
      ..nextDisable = stop
      ..pending.add(
        const AppBlockRequest(packageName: 'com.old.payment', label: 'Old app'),
      );
    await _pumpHost(
      tester,
      gateway,
      policy: const AppLockPolicy(),
      store: store,
    );
    final need = find.byKey(const ValueKey('app-block-need'));
    await tester.ensureVisible(need);
    await tester.pumpAndSettle();
    await tester.tap(need);
    await tester.pumpAndSettle();
    final reason = find.byKey(const ValueKey('app-block-reason-work'));
    await tester.ensureVisible(reason);
    await tester.tap(reason);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    final open = find.byKey(const ValueKey('app-block-open'));
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    final writesBefore = store.writes;
    store.nextWrite = save;
    await tester.tap(open);
    await tester.pump();
    expect(store.waitingForWrite, isTrue);
    expect(gateway.grants, isEmpty);

    stop.complete(const AppLockResult.ok());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('app-block-screen'), skipOffstage: false),
      findsNothing,
    );
    expect(store.waitingForWrite, isTrue);
    save.complete();
    await tester.pumpAndSettle();
    expect(store.waitingForWrite, isFalse);
    expect(
      store.writes,
      writesBefore + 1,
      reason: 'the saved record can finish after its prompt is dismissed',
    );
    expect(
      gateway.grants,
      isEmpty,
      reason: 'a dismissed prompt must not issue a later native grant',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('throwing disable stays unconfirmed and protected package '
      'payloads never open a block screen', (tester) async {
    final gateway = _ControlledGateway()..throwOnDisable = true;
    final container = await _pumpHost(
      tester,
      gateway,
      policy: const AppLockPolicy(),
    );
    expect(container.read(appLockNativeStateUnconfirmedProvider), isTrue);
    expect(find.textContaining('Private stop exception'), findsNothing);
    for (final package in [
      'com.android.dialer',
      'com.android.settings',
      'com.google.android.apps.maps',
      'com.android.launcher3',
      'com.nolean.no_lean',
      'com.nolean.no_lean.preview',
    ]) {
      gateway.pushBlock(
        AppBlockRequest(packageName: package, label: 'Essential'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-block-screen')), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sync failure keeps usage and overlay warnings visible together',
    (tester) async {
      final gateway = _ControlledGateway()
        ..currentStatus = const AppLockStatus(supported: true);
      await _pumpHost(tester, gateway);
      expect(find.textContaining('APP LOCK NOT READY'), findsOneWidget);
      expect(find.textContaining('Usage access is off'), findsOneWidget);
      expect(find.textContaining('Display over other apps'), findsOneWidget);
      expect(find.textContaining('APP LOCK STOPPED'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('app-lock-health-retry')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('app-lock-health-fix')), findsOneWidget);
    },
  );

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
