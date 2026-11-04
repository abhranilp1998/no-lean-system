import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/presentation/relapse_auth_dialog.dart';
import '../application/app_lock_providers.dart';
import '../domain/exit_plan.dart';
import '../domain/locked_app.dart';
import '../domain/never_lockable.dart';
import '../services/app_lock_gateway.dart';
import 'app_lock_disclosure.dart';
import 'app_lock_banner.dart';
import 'app_picker_screen.dart';

/// Saves [next]; loosening asks for biometrics/PIN like other protected
/// settings. Returns true when saved.
Future<bool> saveAppLockPolicy(
  BuildContext context,
  WidgetRef ref,
  AppLockPolicy next,
) async {
  final recovery = ref.read(recoveryProvider);
  try {
    var result = await recovery.updateAppLockPolicy(next);
    if (result == ProtectedActionResult.authenticationRequired &&
        context.mounted) {
      final pin = await showRelapsePinDialog(context, actionLabel: 'CONFIRM');
      if (pin == null) return false;
      result = await recovery.updateAppLockPolicy(
        next,
        pin: pin,
        tryBiometrics: false,
      );
    }
    if (result == ProtectedActionResult.completed) return true;
    if (context.mounted) {
      AppNotice.show(context, result.failureMessage, type: AppNoticeType.error);
    }
  } on RecoverySaveException catch (error) {
    if (context.mounted) {
      AppNotice.show(context, error.toString(), type: AppNoticeType.error);
    }
  }
  return false;
}

/// Grants usage access (after the disclosure page) or the overlay.
Future<void> grantAppLockPermissions(
  BuildContext context,
  WidgetRef ref,
) async {
  final gateway = ref.read(appLockGatewayProvider);
  final status = await gateway.status();
  if (!context.mounted) return;
  if (!status.supported) {
    AppNotice.show(context, AppLockResult.notAvailableMessage);
    return;
  }
  if (!status.usageAccess) {
    if (!await AppLockDisclosure.open(context)) return;
    await gateway.requestPermission();
    return;
  }
  if (!status.overlay) await gateway.requestOverlayPermission();
}

class AppLockSettingsScreen extends ConsumerWidget {
  const AppLockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final policy = recovery.appLockPolicy;
    final status = ref.watch(appLockStatusProvider);
    final pending = ref.watch(appLockSyncPendingProvider);
    final unconfirmed = ref.watch(appLockNativeStateUnconfirmedProvider);

    Future<void> save(AppLockPolicy next) async {
      await saveAppLockPolicy(context, ref, next);
    }

    return Scaffold(
      key: const ValueKey('app-lock-settings'),
      appBar: AppBar(
        title: Text(
          'APP LOCK',
          style: displayFont(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          children: [
            const Text(
              'Lock the apps you use to buy or arrange it. You can always get in for something real (like paying) through "I need this app".',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 14),
            _PermissionCard(status: status),
            const SizedBox(height: 12),
            AppLockHealthBanner(
              onFix: () => grantAppLockPermissions(context, ref),
            ),
            SwitchListTile(
              key: const ValueKey('app-lock-enabled'),
              title: const Text('App lock'),
              subtitle: Text(
                policy.enabled
                    ? policy.apps.isEmpty
                          ? 'On // choose apps below'
                          : 'On // ${policy.enabledPackages.length} app(s)'
                    : unconfirmed
                    ? pending
                          ? 'Off requested // waiting for Android confirmation'
                          : 'Off requested // Android has not confirmed stopping'
                    : 'Off',
              ),
              value: policy.enabled,
              onChanged: (value) => save(policy.copyWith(enabled: value)),
            ),
            const Divider(),
            Text('WHEN', style: eyebrowStyle.copyWith(color: cyan)),
            RadioGroup<AppLockSchedule>(
              groupValue: policy.schedule == AppLockSchedule.custom
                  ? null
                  : policy.schedule,
              onChanged: (value) {
                if (value != null) save(policy.copyWith(schedule: value));
              },
              child: Column(
                children: [
                  for (final schedule in const [
                    AppLockSchedule.always,
                    AppLockSchedule.riskWindow,
                    AppLockSchedule.off,
                  ])
                    RadioListTile<AppLockSchedule>(
                      key: ValueKey('app-lock-schedule-${schedule.name}'),
                      title: Text(schedule.label),
                      subtitle: Text(switch (schedule) {
                        AppLockSchedule.always => 'All day, every day',
                        AppLockSchedule.riskWindow => recovery.riskWindow.label,
                        _ => 'Only while you are inside a danger zone',
                      }),
                      value: schedule,
                    ),
                ],
              ),
            ),
            SwitchListTile(
              key: const ValueKey('app-lock-zones'),
              title: const Text('Also lock inside danger zones'),
              subtitle: Text(
                recovery.zones.isEmpty
                    ? 'No danger zones marked yet'
                    : '${recovery.zones.length} zone(s) // uses your last known location',
              ),
              value: policy.lockInsideDangerZones,
              onChanged: (value) =>
                  save(policy.copyWith(lockInsideDangerZones: value)),
            ),
            const Divider(),
            Text('EXIT PLAN', style: eyebrowStyle.copyWith(color: cyan)),
            const SizedBox(height: 6),
            GlassCard(
              accent: purple,
              child: Text(
                'I need this app → pick a reason → '
                '${ExitPlanTimings.standardWait.inSeconds} s wait with your reasons '
                '(${ExitPlanTimings.paymentWait.inSeconds} s for payment apps) → '
                'that app opens for ${ExitPlanTimings.unlockFor.inMinutes} min. '
                'After ${policy.dailyUnlockBudget} a day your PIN is needed'
                '${recovery.appUnlockPinConfigured ? '' : ' (no PIN set: a ${ExitPlanTimings.longWait.inSeconds} s wait instead)'}. '
                'SOS, Call 112 and Go home are always there.',
                style: const TextStyle(fontSize: 12, height: 1.45),
              ),
            ),
            ListTile(
              key: const ValueKey('app-lock-budget'),
              title: const Text('Unlocks per day before PIN'),
              subtitle: Text('${recovery.appUnlocksLeftToday} left today'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('app-lock-budget-down'),
                    icon: const Icon(Icons.remove),
                    onPressed: policy.dailyUnlockBudget <= 0
                        ? null
                        : () => save(
                            policy.copyWith(
                              dailyUnlockBudget: policy.dailyUnlockBudget - 1,
                            ),
                          ),
                  ),
                  Text(
                    '${policy.dailyUnlockBudget}',
                    key: const ValueKey('app-lock-budget-value'),
                  ),
                  IconButton(
                    key: const ValueKey('app-lock-budget-up'),
                    icon: const Icon(Icons.add),
                    onPressed:
                        policy.dailyUnlockBudget >=
                            AppLockPolicy.maxDailyUnlockBudget
                        ? null
                        : () => save(
                            policy.copyWith(
                              dailyUnlockBudget: policy.dailyUnlockBudget + 1,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'LOCKED APPS',
                    style: eyebrowStyle.copyWith(color: cyan),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('app-lock-choose'),
                  onPressed: () async {
                    final picked = await AppPickerScreen.open(
                      context,
                      selected: policy.apps,
                    );
                    if (picked != null && context.mounted) {
                      await save(policy.copyWith(apps: picked));
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('CHOOSE APPS'),
                ),
              ],
            ),
            if (policy.apps.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No apps locked yet.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            for (final app in policy.apps)
              ListTile(
                key: ValueKey('app-lock-app-${app.packageName}'),
                contentPadding: EdgeInsets.zero,
                title: Text(app.label),
                subtitle: Text(
                  app.paymentApp
                      ? 'Payment app // ${ExitPlanTimings.paymentWait.inSeconds} s quick path'
                      : app.packageName,
                  style: microStyle,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: 'Payment app',
                      child: FilterChip(
                        key: ValueKey('app-lock-payment-${app.packageName}'),
                        label: const Text('PAY'),
                        selected: app.paymentApp,
                        onSelected: (value) => save(
                          policy.copyWith(
                            apps: [
                              for (final item in policy.apps)
                                item.packageName == app.packageName
                                    ? item.copyWith(paymentApp: value)
                                    : item,
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('app-lock-remove-${app.packageName}'),
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => save(
                        policy.copyWith(
                          apps: [
                            for (final item in policy.apps)
                              if (item.packageName != app.packageName) item,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Never locked: phone and emergency calling, maps and navigation, NO LEAN, system settings and your home screen. '
              'Suggested payment apps: ${suggestedPaymentPackages.values.join(', ')}.',
              style: const TextStyle(
                color: muted,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends ConsumerWidget {
  const _PermissionCard({required this.status});

  final AppLockStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = this.status;
    final supported = status?.supported ?? false;
    Widget row(String label, bool ok, String key) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        key: ValueKey(key),
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? toxic : magenta,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
          Text(ok ? 'ON' : 'OFF', style: microStyle),
        ],
      ),
    );
    final missing = supported && (!status!.usageAccess || !status.overlay);
    return GlassCard(
      accent: missing ? magenta : cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PERMISSIONS', style: eyebrowStyle.copyWith(color: cyan)),
          if (!supported)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'App lock runs on Android only.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            )
          else ...[
            row('Usage access', status!.usageAccess, 'app-lock-perm-usage'),
            row(
              'Display over other apps',
              status.overlay,
              'app-lock-perm-overlay',
            ),
            row(
              'Lock service running',
              status.serviceRunning,
              'app-lock-perm-service',
            ),
          ],
          if (missing) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('app-lock-grant'),
              style: FilledButton.styleFrom(backgroundColor: magenta),
              onPressed: () => unawaited(grantAppLockPermissions(context, ref)),
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(
                status.usageAccess
                    ? 'GRANT DISPLAY OVER APPS'
                    : 'GRANT USAGE ACCESS',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
