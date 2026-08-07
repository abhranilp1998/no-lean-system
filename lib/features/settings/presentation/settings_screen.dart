import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/brand_header.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/services/notification_service.dart';
import '../services/biometric_service.dart';
import '../services/recovery_export_service.dart';
import 'settings_dialogs.dart';
import 'widgets/settings_controls.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
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
              icon: Icons.ios_share,
              title: 'Export recovery data',
              subtitle: 'Portable JSON file',
              color: purple,
              onTap: () => exportRecoveryData(context, recovery),
            ),
          ],
        ),
        SettingsSection(
          title: 'INTERFACE',
          children: [
            SettingToggle(
              title: 'CRT scanlines',
              subtitle: 'Subtle display texture',
              value: recovery.scanlines,
              color: cyan,
              onChanged: (value) =>
                  ref.read(recoveryProvider).setSetting('scanlines', value),
            ),
            SettingToggle(
              title: 'Reduce motion',
              subtitle: 'Softer transitions and glow',
              value: recovery.reduceMotion,
              color: toxic,
              onChanged: (value) =>
                  ref.read(recoveryProvider).setSetting('reduceMotion', value),
            ),
            SettingToggle(
              title: 'High contrast',
              subtitle: 'Increase edge and text separation',
              value: recovery.highContrast,
              color: purple,
              onChanged: (value) =>
                  ref.read(recoveryProvider).setSetting('highContrast', value),
            ),
            SettingIntensity(
              value: recovery.intensity,
              onChanged: (value) =>
                  ref.read(recoveryProvider).setSetting('intensity', value),
            ),
          ],
        ),
        SettingsSection(
          title: 'PROTECTION',
          children: [
            SettingToggle(
              title: 'Risk-window reminders',
              subtitle: 'Enable the 17:30—20:00 interrupt window',
              value: recovery.riskReminders,
              color: red,
              onChanged: (value) async {
                await ref
                    .read(recoveryProvider)
                    .setSetting('riskReminders', value);
                if (value) {
                  await NotificationService.instance.scheduleRiskWindow(
                    recovery.reminderMessages,
                  );
                } else {
                  await NotificationService.instance.cancelRiskWindow();
                }
              },
            ),
            SettingToggle(
              title: 'Relapse lock',
              subtitle: recovery.requirePinAfterRelapse
                  ? 'PIN gate enabled'
                  : 'Protect history after a relapse',
              value: recovery.requirePinAfterRelapse,
              color: magenta,
              onChanged: (value) => showPinSetup(context, ref, value),
            ),
            SettingAction(
              icon: Icons.fingerprint,
              title: 'Test device biometrics',
              subtitle: 'Use fingerprint / face unlock when available',
              color: cyan,
              onTap: () => testBiometricAvailability(context),
            ),
          ],
        ),
        const SettingsSection(
          title: 'ABOUT THE BUILD',
          children: [
            GlassCard(
              accent: muted,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NO LEAN  /  MVP 01',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
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
