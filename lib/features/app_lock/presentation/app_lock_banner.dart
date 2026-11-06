import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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
  DateTime? now,
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
    } else if (status.heartbeatStale(now ?? DateTime.now())) {
      messages.add(
        'APP LOCK NOT RESPONDING // The lock has not checked in for a few minutes. Open App Lock settings or turn battery saving off for NO LEAN.',
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

/// The one-word shield state for the home screen (plan P0-1).
enum ShieldState { on, limited, off, notSetUp }

/// Pure so the rules are unit-tested. `limited` = locks, but only by
/// notification (overlay off).
ShieldState shieldStateFor({
  required bool enabled,
  required bool armed,
  required AppLockStatus? status,
  DateTime? now,
}) {
  if (!enabled) return ShieldState.notSetUp;
  if (!armed) return ShieldState.off;
  if (status == null || !status.supported) return ShieldState.on;
  if (!status.usageAccess || !status.serviceRunning) return ShieldState.off;
  if (status.heartbeatStale(now ?? DateTime.now())) return ShieldState.off;
  if (!status.overlay) return ShieldState.limited;
  return ShieldState.on;
}

/// Always-visible "SHIELD ON / OFF" pill. Tapping opens App Lock settings.
class ShieldStatusPill extends ConsumerWidget {
  const ShieldStatusPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final policy = ref.watch(recoveryProvider).appLockPolicy;
    final status = ref.watch(appLockStatusProvider);
    if (status != null && !status.supported) return const SizedBox.shrink();
    final state = shieldStateFor(
      enabled: policy.enabled,
      armed: policy.armed,
      status: status,
    );
    final (label, detail, color) = switch (state) {
      ShieldState.on => ('SHIELD ON', 'Locked apps are guarded', toxic),
      ShieldState.limited => (
        'SHIELD LIMITED',
        'Notification only. Tap to fix',
        magenta,
      ),
      ShieldState.off => ('SHIELD OFF', 'Nothing is locked. Tap to fix', red),
      ShieldState.notSetUp => (
        'SHIELD OFF',
        'Lock payment apps at risky times. Tap to set up',
        muted,
      ),
    };
    return Semantics(
      button: true,
      label: '$label. $detail',
      child: InkWell(
        key: const ValueKey('shield-status-pill'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AppLockSettingsScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: .6)),
            color: color.withValues(alpha: .08),
          ),
          child: Row(
            children: [
              Icon(
                state == ShieldState.on
                    ? Icons.shield_outlined
                    : Icons.gpp_maybe_outlined,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  detail,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
              const Icon(Icons.chevron_right, color: muted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
