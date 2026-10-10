import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_lock_gateway.dart';

/// TODO(app-lock): swap for the MethodChannel-backed gateway on Android.
final appLockGatewayProvider = Provider<AppLockGateway>(
  (ref) => const UnsupportedAppLockGateway(),
);

/// Whether app locking can be used. The Settings tile reads this.
final appLockAvailabilityProvider = FutureProvider<AppLockAvailability>(
  (ref) => ref.watch(appLockGatewayProvider).availability(),
);
