import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recovery/application/recovery_provider.dart';
import '../application/app_lock_providers.dart';
import '../services/app_lock_gateway.dart';
import 'app_lock_settings_screen.dart';

/// What the in-app fail-safe banner should say, or null when all is well.
/// Pure so the fail-safe rules are unit-tested.
String? appLockHealthMessage({
  required bool armed,
  required AppLockStatus? status,
}) {
  if (!armed || status == null || !status.supported) return null;
  if (!status.usageAccess) {
    return 'APP LOCK PAUSED // Usage access is off, so nothing is being locked. Grant it again to resume.';
  }
  if (!status.overlay) {
    return 'APP LOCK LIMITED // "Display over other apps" is off, so locked apps only get a notification.';
  }
  if (!status.serviceRunning) {
    return 'APP LOCK STOPPED // Android stopped the lock service. Nothing is locked until it restarts.';
  }
  return null;
}

/// In-app banner when the app lock is on but can't enforce (permission
/// revoked, service killed). Never blocks anything itself.
class AppLockHealthBanner extends ConsumerWidget {
  const AppLockHealthBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final armed = ref.watch(recoveryProvider).appLockPolicy.armed;
    final message = appLockHealthMessage(
      armed: armed,
      status: ref.watch(appLockStatusProvider),
    );
    if (message == null) return const SizedBox.shrink();
    return MaterialBanner(
      key: const ValueKey('app-lock-health-banner'),
      content: Text(message),
      actions: [
        TextButton(
          key: const ValueKey('app-lock-health-fix'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AppLockSettingsScreen()),
          ),
          child: const Text('FIX'),
        ),
      ],
    );
  }
}
