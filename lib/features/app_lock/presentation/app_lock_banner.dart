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
  AppLockSyncFailure? syncFailure,
  bool deactivationPending = false,
}) {
  final messages = <String>[];
  if (syncFailure != null) {
    messages.add(switch (syncFailure) {
      AppLockSyncFailure.activation =>
        'APP LOCK NOT READY // Android did not confirm activation. Retry or check App Lock settings.',
      AppLockSyncFailure.deactivation =>
        'APP LOCK UPDATE FAILED // Android did not confirm turning app lock off. Apps may still be blocked. Retry or check App Lock settings.',
    });
  } else if (deactivationPending) {
    messages.add(
      'APP LOCK TURNING OFF // Waiting for Android to confirm. Apps may still be blocked.',
    );
  }
  if (armed && status != null && status.supported) {
    if (!status.usageAccess) {
      messages.add(
        'APP LOCK PAUSED // Usage access is off, so nothing is being locked. Grant it again to resume.',
      );
    }
    if (!status.overlay) {
      messages.add(
        'APP LOCK LIMITED // "Display over other apps" is off, so locked apps only get a notification.',
      );
    }
    if (!status.serviceRunning) {
      messages.add(
        'APP LOCK STOPPED // Android stopped the lock service. Nothing is locked until it restarts.',
      );
    }
  }
  return messages.isEmpty ? null : messages.join('\n\n');
}

/// In-app banner when the app lock is on but can't enforce (permission
/// revoked, service killed). Never blocks anything itself.
class AppLockHealthBanner extends ConsumerWidget {
  const AppLockHealthBanner({this.onFix, super.key});

  /// Settings can fix permissions in place rather than opening itself again.
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(recoveryProvider).appLockPolicy;
    final syncFailure = ref.watch(appLockSyncFailureProvider);
    final pending = ref.watch(appLockSyncPendingProvider);
    final message = appLockHealthMessage(
      armed: policy.armed || ref.watch(appLockNativeStateUnconfirmedProvider),
      status: ref.watch(appLockStatusProvider),
      syncFailure: syncFailure,
      deactivationPending: pending && !policy.armed,
    );
    if (message == null) return const SizedBox.shrink();
    final messages = message.split('\n\n');
    return MaterialBanner(
      key: const ValueKey('app-lock-health-banner'),
      // The shell places this above an Expanded body. Multiple simultaneous
      // warnings must not consume the whole screen, especially at large text.
      // Keep actions outside the message viewport so recovery remains usable.
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .25,
        ),
        child: Scrollbar(
          interactive: false,
          child: SingleChildScrollView(
            key: const ValueKey('app-lock-health-messages'),
            primary: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < messages.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == messages.length - 1 ? 0 : 16,
                    ),
                    child: Text(messages[index]),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (syncFailure != null)
          TextButton(
            key: const ValueKey('app-lock-health-retry'),
            onPressed: () => ref.read(appLockRetryProvider.notifier).state++,
            child: const Text('RETRY'),
          ),
        TextButton(
          key: const ValueKey('app-lock-health-fix'),
          onPressed:
              onFix ??
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AppLockSettingsScreen(),
                ),
              ),
          child: const Text('FIX'),
        ),
      ],
    );
  }
}
