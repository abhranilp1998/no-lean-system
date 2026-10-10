import '../../../core/layout/tab_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/services/feedback_preferences.dart';
import '../../../core/services/save_action.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/brand_header.dart';
import '../../../core/widgets/glass_card.dart';
import '../../app_lock/application/app_lock_providers.dart';
import '../../app_lock/domain/locked_app.dart';
import '../../app_lock/presentation/app_lock_settings_screen.dart';
import '../../app_lock/services/app_lock_gateway.dart';
import '../../recovery/application/recovery_provider.dart';
import '../services/biometric_service.dart';
import '../services/recovery_export_service.dart';
import 'settings_dialogs.dart';
import 'trusted_contact_dialog.dart';
import 'widgets/settings_controls.dart';
import '../../zones/presentation/zones_screen.dart';
import '../../recovery/domain/dose_units.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    return TabListView(
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text('SETTINGS', style: eyebrowStyle.copyWith(color: cyan)),
        const SizedBox(height: 7),
        Text(
          'Tune the override.',
          style: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 22),
        SettingsSection(
          title: 'PERSONAL DATA',
          children: [
            SettingAction(
              icon: Icons.edit_note,
              title: 'Reasons for quitting',
              subtitle: '${recovery.reasons.length} reasons loaded',
              color: magenta,
              onTap: () => showReasonsDialog(context, ref),
            ),
            SettingAction(
              icon: Icons.notifications_active_outlined,
              title: 'Reminder messages',
              subtitle: '${recovery.reminderMessages.length} blunt reminders',
              color: cyan,
              onTap: () => showReminderDialog(context, ref),
            ),
            SettingAction(
              icon: Icons.payments_outlined,
              title: 'Average daily spend',
              subtitle: '${money(recovery.dailySpend)} per day',
              color: toxic,
              onTap: () => showSpendDialog(context, ref),
            ),
            SettingAction(
              key: const ValueKey('settings-bottle-size'),
              icon: Icons.local_drink_outlined,
              title: 'Bottle size',
              subtitle:
                  '${formatMl(recovery.bottleMl)} per bottle // new entries only',
              color: magenta,
              onTap: () => showBottleSizeDialog(context, ref),
            ),
            SettingAction(
              icon: Icons.ios_share,
              title: 'Export backup',
              subtitle: 'Portable JSON file',
              color: cyan,
              onTap: () => exportRecoveryData(context, recovery),
            ),
            SettingAction(
              key: const ValueKey('settings-export-csv'),
              icon: Icons.table_view_outlined,
              title: 'Export history (CSV)',
              subtitle: 'Every event, spreadsheet-ready // read-only copy',
              color: toxic,
              onTap: () => exportRecoveryCsv(context, recovery),
            ),
            SettingAction(
              icon: Icons.download_outlined,
              title: 'Import backup',
              subtitle: 'Merge events from file',
              color: purple,
              onTap: () => importRecoveryData(context, ref),
            ),
          ],
        ),
        SettingsSection(
          title: 'INTERFACE',
          children: [
            SettingAction(
              icon: Icons.dashboard_customize_outlined,
              title: 'Dashboard messages',
              subtitle:
                  '${recovery.dashboardNoticeStyle.label} // counter stays first',
              color: cyan,
              onTap: () => showDashboardNoticeStyleDialog(context, ref),
            ),
            SettingToggle(
              title: 'CRT scanlines',
              subtitle: 'Subtle display texture',
              value: recovery.scanlines,
              color: cyan,
              onChanged: (value) => saveAction(
                context,
                () => ref.read(recoveryProvider).setSetting('scanlines', value),
              ),
            ),
            SettingToggle(
              title: 'Reduce motion',
              subtitle: 'Softer transitions and glow',
              value: recovery.reduceMotion,
              color: toxic,
              onChanged: (value) => saveAction(
                context,
                () => ref
                    .read(recoveryProvider)
                    .setSetting('reduceMotion', value),
              ),
            ),
            SettingToggle(
              title: 'High contrast',
              subtitle: 'Increase edge and text separation',
              value: recovery.highContrast,
              color: purple,
              onChanged: (value) => saveAction(
                context,
                () => ref
                    .read(recoveryProvider)
                    .setSetting('highContrast', value),
              ),
            ),
            SettingAction(
              icon: Icons.graphic_eq,
              title: 'Tap feedback',
              subtitle:
                  '${recovery.soundscape ? recovery.feedbackSound.label : 'SOUND OFF'} // VIBRATION ${recovery.hapticFeedback ? 'ON' : 'OFF'}',
              color: magenta,
              onTap: () => showFeedbackDialog(context, ref),
            ),
            SettingIntensity(
              value: recovery.intensity,
              onChanged: (value) => saveAction(
                context,
                () => ref.read(recoveryProvider).setSetting('intensity', value),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'PROTECTION',
          children: [
            SettingAction(
              icon: Icons.contact_emergency,
              title: 'Trusted contact',
              subtitle: 'Emergency dial during SOS',
              color: cyan,
              onTap: () => showTrustedContactDialog(context, ref),
            ),
            SettingAction(
              icon: Icons.schedule,
              title: 'Risk window',
              subtitle:
                  '${recovery.riskWindow.label} // 15-min warning + 4 interrupts',
              color: purple,
              onTap: () => showRiskWindowDialog(context, ref),
            ),
            SettingAction(
              key: const ValueKey('settings-quiet-hours'),
              icon: Icons.bedtime_outlined,
              title: 'Quiet hours',
              subtitle: recovery.notificationPrefs.quietHoursEnabled
                  ? '${recovery.notificationPrefs.quietHours.label} // risk + zone alerts still on'
                  : 'Off // mute non-critical notifications overnight',
              color: purple,
              onTap: () => showQuietHoursDialog(context, ref),
            ),
            SettingAction(
              key: const ValueKey('settings-danger-zones'),
              icon: Icons.dangerous_outlined,
              title: 'Danger zones',
              subtitle:
                  '${recovery.zones.length} marked // ${recovery.streetTiles ? 'street map' : 'grid map'}${recovery.zoneMonitoring || recovery.backgroundGeofencing ? ' // alerts on' : ''}',
              color: red,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ZonesScreen())),
            ),
            SettingToggle(
              key: const ValueKey('settings-position-notification'),
              title: 'Position notification',
              subtitle: recovery.positionNotification
                  ? 'Quiet, always-on position status while the app is open // zone alerts unchanged'
                  : 'Off // zone alerts still work as set',
              value: recovery.positionNotification,
              color: cyan,
              onChanged: (value) => saveAction(
                context,
                () => ref.read(recoveryProvider).setPositionNotification(value),
              ),
            ),
            SettingAction(
              key: const ValueKey('settings-app-lock'),
              icon: Icons.app_blocking_outlined,
              title: 'App lock',
              subtitle: _appLockSubtitle(
                recovery.appLockPolicy,
                ref.watch(appLockStatusProvider),
              ),
              color: magenta,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AppLockSettingsScreen(),
                ),
              ),
            ),
            SettingAction(
              icon: Icons.hourglass_bottom,
              title: 'Relapse reset window',
              subtitle: '${recovery.cooldownMinutes} minute guided pause',
              color: magenta,
              onTap: () => showCooldownDialog(context, ref),
            ),
            SettingToggle(
              title: 'Peak-hour lock',
              subtitle:
                  'Hold-to-open relapse logging during ${recovery.riskWindow.label}',
              value: recovery.peakHourLock,
              color: magenta,
              onChanged: (value) => saveAction(
                context,
                () => ref
                    .read(recoveryProvider)
                    .setSetting('peakHourLock', value),
              ),
            ),
            SettingToggle(
              title: 'Risk-window reminders',
              subtitle:
                  'Strong ${recovery.riskWindow.label} interrupts using your risk data',
              value: recovery.riskReminders,
              color: red,
              onChanged: (value) => saveAction(
                context,
                () => ref
                    .read(recoveryProvider)
                    .setSetting('riskReminders', value),
              ),
            ),
            if (recovery.riskReminders)
              SettingAction(
                icon: Icons.alarm_on,
                title: 'Exact alert timing',
                subtitle:
                    'Allow exact alarms so alerts land on time; otherwise Android may delay them',
                color: red,
                onTap: () => requestExactAlertTiming(context, ref),
              ),
            SettingToggle(
              title: 'Relapse lock',
              subtitle: recovery.requirePinAfterRelapse
                  ? 'Biometric first // hashed PIN fallback'
                  : 'Authenticate before resetting clean time',
              value: recovery.requirePinAfterRelapse,
              color: magenta,
              onChanged: (value) => showPinSetup(context, ref, value),
            ),
            if (recovery.requirePinAfterRelapse)
              SettingToggle(
                title: 'Risk-window lock',
                subtitle:
                    'PIN / biometric wall during ${recovery.riskWindow.label} // SOS stays open',
                value: recovery.riskWindowLock,
                color: magenta,
                onChanged: (value) => setRiskWindowLock(context, ref, value),
              ),
            SettingAction(
              icon: Icons.fingerprint,
              title: 'Verify biometrics',
              subtitle: 'Run a real fingerprint / face authentication',
              color: cyan,
              onTap: () => verifyBiometricAuthentication(context),
            ),
          ],
        ),
        SettingsSection(
          title: 'PRIVACY',
          children: [
            SettingToggle(
              key: const ValueKey('settings-street-tiles'),
              title: 'Street map tiles',
              subtitle: recovery.streetTiles
                  ? 'OpenStreetMap tiles on the zone map // cached once viewed'
                  : 'Off // grid map only, no network requests',
              value: recovery.streetTiles,
              color: cyan,
              onChanged: (value) => saveAction(
                context,
                () => ref.read(recoveryProvider).setStreetTiles(value),
              ),
            ),
            SettingToggle(
              key: const ValueKey('settings-zone-history'),
              title: 'Zone visit history',
              subtitle: recovery.zoneHistory
                  ? 'Logs zone name + time on entry // never coordinates'
                  : 'Off // zone entries alert but are not recorded',
              value: recovery.zoneHistory,
              color: red,
              onChanged: (value) => saveAction(
                context,
                () => ref.read(recoveryProvider).setZoneHistory(value),
              ),
            ),
            if (recovery.zoneEntryCount > 0)
              SettingAction(
                key: const ValueKey('settings-clear-zone-history'),
                icon: Icons.delete_sweep_outlined,
                title: 'Clear zone history',
                subtitle:
                    '${recovery.zoneEntryCount} recorded '
                    '${recovery.zoneEntryCount == 1 ? 'entry' : 'entries'} // '
                    'removed from this device',
                color: red,
                onTap: () => confirmClearZoneHistory(context, ref),
              ),
            SettingToggle(
              key: const ValueKey('settings-widget-privacy'),
              title: 'Private home widget',
              subtitle: recovery.widgetPrivacy
                  ? 'Neutral labels // no counter, streak or risk state'
                  : 'Widget shows clean time, streak and risk window',
              value: recovery.widgetPrivacy,
              color: cyan,
              onChanged: (value) => saveAction(
                context,
                () => ref.read(recoveryProvider).setWidgetPrivacy(value),
              ),
            ),
            SettingToggle(
              key: const ValueKey('settings-hide-sensitive'),
              title: 'Hide sensitive content',
              subtitle: recovery.notificationPrefs.hideSensitive
                  ? 'Notifications read "Reminder" // no recovery wording'
                  : 'Notifications show full text // lock screen still redacted',
              value: recovery.notificationPrefs.hideSensitive,
              color: cyan,
              onChanged: (value) => saveAction(
                context,
                () => ref
                    .read(recoveryProvider)
                    .setHideSensitiveNotifications(value),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'ABOUT THE BUILD',
          children: [
            GlassCard(
              accent: muted,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<PackageInfo>(
                    future: _packageInfo,
                    builder: (context, snapshot) {
                      final info = snapshot.data;
                      final version = info == null
                          ? 'VERSION LOADING'
                          : 'VERSION ${info.version} (${info.buildNumber})';
                      return Text(
                        'NO LEAN  /  $version',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Offline-first recovery tracking with a direct voice, local data, a risk-window interrupt, SOS breathing timer, data export, and Android widget support.',
                    style: TextStyle(color: muted, fontSize: 11, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _appLockSubtitle(AppLockPolicy policy, AppLockStatus? status) {
  if (!policy.enabled) return 'Off // lock chosen apps, with an exit plan';
  final apps = policy.enabledPackages.length;
  final when = policy.schedule == AppLockSchedule.off
      ? 'danger zones'
      : policy.schedule.label.toLowerCase();
  final health = status != null && status.supported && !status.usageAccess
      ? ' // needs usage access'
      : '';
  return '$apps app(s) // $when${policy.lockInsideDangerZones && policy.schedule != AppLockSchedule.off ? ' + zones' : ''}$health';
}
