import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recovery/application/recovery_provider.dart';
import '../domain/native_config.dart';
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
        } else {
          ref.read(appLockSyncFailureProvider.notifier).state = activating
              ? AppLockSyncFailure.activation
              : AppLockSyncFailure.deactivation;
        }
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
      }
    }
  }

  Future<void> _drain() async {
    if (!mounted || _blockOpen) return;
    final requests = await _gateway.drainBlockRequests();
    if (!mounted || requests.isEmpty || _blockOpen) return;
    final request = requests.last;
    final policy = ref.read(recoveryProvider).appLockPolicy;
    // Stale request (app removed or lock turned off since): ignore it.
    if (!policy.enabled ||
        !policy.enabledPackages.contains(request.packageName)) {
      return;
    }
    _blockOpen = true;
    try {
      await AppBlockScreen.open(context, request);
    } finally {
      _blockOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(recoveryProvider, (_, _) => unawaited(_sync()));
    ref.listen(appLockRetryProvider, (_, _) => unawaited(_sync(force: true)));
    return widget.child;
  }
}
