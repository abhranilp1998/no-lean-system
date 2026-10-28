import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recovery/application/recovery_provider.dart';
import '../domain/native_config.dart';
import '../domain/never_lockable.dart';
import '../presentation/app_block_screen.dart';
import '../services/app_lock_gateway.dart';
import 'app_lock_providers.dart';

/// Keeps the native app-lock service in step with the saved policy and
/// shows the blocking screen when a locked app comes to the front.
///
/// - Pushes the native config whenever the policy, risk window, zones or
///   notification privacy change (and on start/resume, which also restarts
///   a service the OS killed).
/// - Refreshes [appLockStatusProvider] for the re-grant banner.
/// - Drains block requests and opens [AppBlockScreen] once at a time.
class AppLockHost extends ConsumerStatefulWidget {
  const AppLockHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockHost> createState() => _AppLockHostState();
}

class _AppLockHostState extends ConsumerState<AppLockHost>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _blocks;
  String? _acknowledgedConfig;
  bool _blockOpen = false;
  Route<void>? _blockRoute;
  String? _blockingPackage;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _syncAgainForce = false;

  AppLockGateway get _gateway => ref.read(appLockGatewayProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _blocks = _gateway.blockRequestsAvailable.listen((_) => _drain());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_sync(force: true));
      unawaited(_drain());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blocks?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_sync(force: true));
      unawaited(_drain());
    }
  }

  Future<void> _sync({bool force = false}) async {
    if (!mounted) return;
    if (_syncing) {
      _syncAgain = true;
      _syncAgainForce = _syncAgainForce || force;
      return;
    }
    _syncing = true;
    try {
      final recovery = ref.read(recoveryProvider);
      if (!recovery.isLoaded) return;
      if (!_gateway.isSupportedPlatform) {
        _acknowledgedConfig = null;
        ref.read(appLockSyncPendingProvider.notifier).state = false;
        ref.read(appLockSyncFailureProvider.notifier).state = null;
        ref.read(appLockStatusProvider.notifier).state =
            const AppLockStatus.unsupported();
        return;
      }
      final config = buildNativeAppLockConfig(
        policy: recovery.appLockPolicy,
        riskWindow: recovery.riskWindow,
        zones: recovery.zones,
        hideSensitive: recovery.notificationPrefs.hideSensitive,
      );
      final encoded = jsonEncode(config);
      if (force || encoded != _acknowledgedConfig) {
        // A failed replacement may have changed native state before failing.
        // Neither the requested config nor an older one is acknowledged then.
        _acknowledgedConfig = null;
        ref.read(appLockSyncPendingProvider.notifier).state = true;
        final activating = config['enabled'] == true;
        AppLockResult? result;
        try {
          result = activating
              ? await _gateway.apply(config)
              : await _gateway.disable();
        } catch (_) {
          // Report the failed update without exposing native exception data.
        }
        if (!mounted) return;
        if (result?.supported == true) {
          _acknowledgedConfig = encoded;
          ref.read(appLockSyncFailureProvider.notifier).state = null;
          // A confirmed stop/removal makes an already-open prompt stale.
          // Remove only that route, preserving an SOS route above it.
          final packages = config['packages'];
          if (!activating ||
              (packages is List && !packages.contains(_blockingPackage))) {
            final route = _blockRoute;
            if (route != null && route.isActive) {
              route.navigator?.removeRoute(route);
            }
          }
        } else {
          ref.read(appLockSyncFailureProvider.notifier).state = activating
              ? AppLockSyncFailure.activation
              : AppLockSyncFailure.deactivation;
        }
        final current = ref.read(recoveryProvider);
        final stillRequested =
            encoded ==
            jsonEncode(
              buildNativeAppLockConfig(
                policy: current.appLockPolicy,
                riskWindow: current.riskWindow,
                zones: current.zones,
                hideSensitive: current.notificationPrefs.hideSensitive,
              ),
            );
        // An older write can complete after the user requested a newer policy.
        // Do not briefly report the newer request as settled while status is
        // being read; its queued write must be acknowledged first.
        ref.read(appLockSyncPendingProvider.notifier).state = !stillRequested;
        if (!stillRequested) _syncAgain = true;
      }
      final status = await _gateway.status();
      if (mounted) ref.read(appLockStatusProvider.notifier).state = status;
    } catch (_) {
      // A health-read failure must not trap navigation or essential actions.
    } finally {
      _syncing = false;
      if (_syncAgain && mounted) {
        final force = _syncAgainForce;
        _syncAgain = false;
        _syncAgainForce = false;
        unawaited(_sync(force: force));
      } else if (mounted) {
        // Cleanup errors must not leave an idle host showing "syncing".
        // A queued successor owns the flag once it has started.
        ref.read(appLockSyncPendingProvider.notifier).state = false;
      }
    }
  }

  Future<void> _drain() async {
    if (!mounted || _blockOpen || !_gateway.isSupportedPlatform) return;
    List<AppBlockRequest> requests;
    try {
      requests = await _gateway.drainBlockRequests();
    } catch (_) {
      // A failed native read can be retried on the next signal or resume.
      return;
    }
    if (!mounted || requests.isEmpty || _blockOpen) return;
    final request = requests.last;
    final recovery = ref.read(recoveryProvider);
    final policy = recovery.appLockPolicy;
    final requestedConfig = jsonEncode(
      buildNativeAppLockConfig(
        policy: policy,
        riskWindow: recovery.riskWindow,
        zones: recovery.zones,
        hideSensitive: recovery.notificationPrefs.hideSensitive,
      ),
    );
    final unconfirmed =
        _acknowledgedConfig != requestedConfig ||
        ref.read(appLockNativeStateUnconfirmedProvider);
    // A saved Off/removal is only a request until Android acknowledges it.
    // Failed writes may partially apply, including after a cold start where
    // Dart has no copy of the old native policy. Keep essential exits available
    // for native requests during that uncertainty; reject known stale requests
    // again after an accepted update. Protected apps remain excluded always.
    if (isNeverLockable(request.packageName) ||
        (!unconfirmed &&
            (!policy.enabled ||
                !policy.enabledPackages.contains(request.packageName)))) {
      return;
    }
    _blockOpen = true;
    _blockingPackage = request.packageName;
    final route = AppBlockScreen.route(request);
    _blockRoute = route;
    try {
      await Navigator.of(context).push(route);
    } finally {
      _blockOpen = false;
      _blockRoute = null;
      _blockingPackage = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(recoveryProvider, (_, _) => unawaited(_sync()));
    ref.listen(appLockRetryProvider, (_, _) => unawaited(_sync(force: true)));
    return widget.child;
  }
}
