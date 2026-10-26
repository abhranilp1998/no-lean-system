import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_lock_gateway.dart';

/// Android gets the real gateway; everything else (and tests by default)
/// gets the unsupported one, which never blocks anything.
final appLockGatewayProvider = Provider<AppLockGateway>(
  (ref) => !kIsWeb && Platform.isAndroid
      ? MethodChannelAppLockGateway()
      : const UnsupportedAppLockGateway(),
);

/// Latest native health, refreshed by `AppLockHost` on start, resume and
/// after every config push. Drives the settings status and the re-grant
/// banner.
final appLockStatusProvider = StateProvider<AppLockStatus?>((ref) => null);

/// A requested native change was not acknowledged. Kept separate from native
/// permissions/service health, which may still describe the previous config.
enum AppLockSyncFailure { activation, deactivation }

final appLockSyncFailureProvider = StateProvider<AppLockSyncFailure?>(
  (ref) => null,
);

/// Explicit retry signal; the host serializes it with policy/lifecycle updates.
final appLockRetryProvider = StateProvider<int>((ref) => 0);

/// Whether app locking can be used.
final appLockAvailabilityProvider = FutureProvider<AppLockAvailability>(
  (ref) => ref.watch(appLockGatewayProvider).availability(),
);
