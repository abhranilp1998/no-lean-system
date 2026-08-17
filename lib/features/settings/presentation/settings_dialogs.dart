import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/services/app_notice.dart';
import '../../../core/services/feedback_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/risk_window.dart';
import '../../recovery/presentation/relapse_auth_dialog.dart';

Future<void> showReasonsDialog(BuildContext context, WidgetRef ref) async {
  final controllers = ref
      .read(recoveryProvider)
      .reasons
      .map((text) => TextEditingController(text: text))
      .toList();
  final updatedReasons = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'WHY YOU ARE DONE',
      child: StatefulBuilder(
        builder: (_, setState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final controller in controllers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Reason',
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => controllers.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('ADD REASON'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      controllers.map((item) => item.text).toList(),
                    );
                  },
                  child: const Text('SAVE REASONS'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  for (final controller in controllers) {
    controller.dispose();
  }
  if (updatedReasons != null && context.mounted) {
    await ref.read(recoveryProvider).updateReasons(updatedReasons);
    if (context.mounted) {
      AppNotice.show(
        context,
        'REASONS UPDATED // OVERRIDE MEMORY ARMED.',
        type: AppNoticeType.success,
      );
    }
  }
}

Future<void> showReminderDialog(BuildContext context, WidgetRef ref) async {
  final controllers = ref
      .read(recoveryProvider)
      .reminderMessages
      .map((text) => TextEditingController(text: text))
      .toList();
  final updatedMessages = await showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'RISK-WINDOW MESSAGES',
      child: StatefulBuilder(
        builder: (_, setState) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final controller in controllers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: TextField(
                    controller: controller,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Reminder',
                    ),
                  ),
                ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => controllers.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('ADD MESSAGE'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      controllers.map((item) => item.text).toList(),
                    );
                  },
                  child: const Text('SAVE MESSAGES'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  for (final controller in controllers) {
    controller.dispose();
  }
  if (updatedMessages != null && context.mounted) {
    await ref.read(recoveryProvider).updateReminders(updatedMessages);
    if (context.mounted) {
      AppNotice.show(
        context,
        'RISK-WINDOW MESSAGES UPDATED.',
        type: AppNoticeType.success,
      );
    }
  }
}

Future<void> showSpendDialog(BuildContext context, WidgetRef ref) async {
  final recovery = ref.read(recoveryProvider);
  final controller = TextEditingController(
    text: recovery.dailySpend > 0 ? recovery.dailySpend.round().toString() : '',
  );
  final updatedSpend = await showDialog<double>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'AVERAGE DAILY SPEND',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              prefixText: '₹  ',
              labelText: 'Amount per day',
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                double.tryParse(controller.text) ?? 0,
              ),
              child: const Text('SAVE'),
            ),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (updatedSpend != null && context.mounted) {
    await ref.read(recoveryProvider).updateDailySpend(updatedSpend);
    if (context.mounted) {
      AppNotice.show(
        context,
        'DAILY SPEND BASELINE UPDATED.',
        type: AppNoticeType.success,
      );
    }
  }
}

Future<void> showRiskWindowDialog(BuildContext context, WidgetRef ref) async {
  final recovery = ref.read(recoveryProvider);
  var startMinutes = recovery.riskWindow.startMinutes;
  var endMinutes = recovery.riskWindow.endMinutes;

  final updatedWindow = await showDialog<RiskWindow>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AppDialog(
        title: 'CONFIGURE RISK WINDOW',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose the hours when interruption matters most. Overnight windows are supported.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 16),
            _TimeSelector(
              label: 'WINDOW START',
              minutes: startMinutes,
              color: magenta,
              onTap: () async {
                final selected = await _pickTime(dialogContext, startMinutes);
                if (selected != null) setState(() => startMinutes = selected);
              },
            ),
            const SizedBox(height: 10),
            _TimeSelector(
              label: 'WINDOW END',
              minutes: endMinutes,
              color: cyan,
              onTap: () async {
                final selected = await _pickTime(dialogContext, endMinutes);
                if (selected != null) setState(() => endMinutes = selected);
              },
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: startMinutes == endMinutes
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        RiskWindow(
                          startMinutes: startMinutes,
                          endMinutes: endMinutes,
                        ),
                      ),
                icon: const Icon(Icons.schedule),
                label: const Text('SAVE WINDOW'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (updatedWindow == null || !context.mounted) return;
  await ref.read(recoveryProvider).updateRiskWindow(updatedWindow);
  if (context.mounted) {
    AppNotice.show(
      context,
      'RISK WINDOW SET // ${updatedWindow.label}',
      type: AppNoticeType.success,
    );
  }
}

Future<void> showFeedbackDialog(BuildContext context, WidgetRef ref) async {
  final recovery = ref.read(recoveryProvider);
  var soundEnabled = recovery.soundscape;
  var vibrationEnabled = recovery.hapticFeedback;
  var soundEffect = recovery.feedbackSound;

  final preferences = await showDialog<FeedbackPreferences>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AppDialog(
        title: 'TAP FEEDBACK MATRIX',
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sound and vibration are independent. Select a signal and audition it before saving.',
                style: TextStyle(color: muted, fontSize: 11, height: 1.45),
              ),
              const SizedBox(height: 12),
              _FeedbackToggle(
                icon: Icons.volume_up_outlined,
                title: 'SOUND EFFECTS',
                subtitle: soundEnabled ? soundEffect.label : 'MUTED',
                value: soundEnabled,
                color: magenta,
                onChanged: (value) {
                  setState(() => soundEnabled = value);
                  if (value) AppFeedback.previewSound(soundEffect);
                },
              ),
              const SizedBox(height: 8),
              _FeedbackToggle(
                icon: Icons.vibration,
                title: 'VIBRATION',
                subtitle: vibrationEnabled ? 'TACTILE SIGNAL ON' : 'DISABLED',
                value: vibrationEnabled,
                color: cyan,
                onChanged: (value) {
                  setState(() => vibrationEnabled = value);
                  if (value) AppFeedback.previewVibration();
                },
              ),
              const SizedBox(height: 18),
              Text('SOUND PROFILE', style: microStyle.copyWith(color: purple)),
              const SizedBox(height: 8),
              for (final effect in FeedbackSoundEffect.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _SoundEffectOption(
                    effect: effect,
                    selected: soundEffect == effect,
                    onTap: () {
                      setState(() {
                        soundEffect = effect;
                        soundEnabled = true;
                      });
                      AppFeedback.previewSound(effect);
                    },
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    FeedbackPreferences(
                      soundEnabled: soundEnabled,
                      vibrationEnabled: vibrationEnabled,
                      soundEffect: soundEffect,
                    ),
                  ),
                  icon: const Icon(Icons.save_outlined, size: 17),
                  label: const Text('SAVE FEEDBACK'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (preferences == null || !context.mounted) return;
  await ref
      .read(recoveryProvider)
      .updateFeedbackPreferences(
        soundEnabled: preferences.soundEnabled,
        vibrationEnabled: preferences.vibrationEnabled,
        soundEffect: preferences.soundEffect,
      );
  if (context.mounted) {
    AppNotice.show(
      context,
      'FEEDBACK UPDATED // SOUND ${preferences.soundEnabled ? preferences.soundEffect.label : 'OFF'} // VIBRATION ${preferences.vibrationEnabled ? 'ON' : 'OFF'}',
      type: AppNoticeType.success,
    );
  }
}

Future<void> showPinSetup(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  if (!enabled) {
    final recovery = ref.read(recoveryProvider);
    var result = await recovery.disableRelapseLock();
    if (result == ProtectedActionResult.authenticationRequired &&
        context.mounted) {
      final pin = await showRelapsePinDialog(
        context,
        actionLabel: 'DISABLE LOCK',
      );
      if (pin == null) return;
      result = await recovery.disableRelapseLock(
        pin: pin,
        tryBiometrics: false,
      );
    }
    if (!context.mounted) return;
    AppNotice.show(
      context,
      result == ProtectedActionResult.completed
          ? 'RELAPSE LOCK DISABLED.'
          : 'AUTHENTICATION FAILED // LOCK REMAINS ACTIVE.',
      type: result == ProtectedActionResult.completed
          ? AppNoticeType.info
          : AppNoticeType.error,
    );
    return;
  }
  final pinController = TextEditingController();
  final confirmController = TextEditingController();
  String? validationMessage;
  final enteredPin = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AppDialog(
        title: 'SET RELAPSE LOCK PIN',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Biometrics will be attempted first. This encrypted PIN is your fallback.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '4–6 digit PIN'),
            ),
            TextField(
              controller: confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Confirm PIN',
                errorText: validationMessage,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final pin = pinController.text;
                  if (pin.length < 4 || pin != confirmController.text) {
                    setState(() {
                      validationMessage = pin.length < 4
                          ? 'Use 4–6 digits.'
                          : 'PIN values do not match.';
                    });
                    return;
                  }
                  Navigator.pop(dialogContext, pin);
                },
                child: const Text('ENABLE SECURE LOCK'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (enteredPin != null && context.mounted) {
    await ref.read(recoveryProvider).enableRelapseLock(enteredPin);
    if (context.mounted) {
      AppNotice.show(
        context,
        'RELAPSE LOCK ARMED // BIOMETRIC + ENCRYPTED PIN.',
        type: AppNoticeType.success,
      );
    }
  }
  pinController.dispose();
  confirmController.dispose();
}

Future<int?> _pickTime(BuildContext context, int initialMinutes) async {
  final selected = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: initialMinutes ~/ 60,
      minute: initialMinutes % 60,
    ),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        timePickerTheme: TimePickerThemeData(
          backgroundColor: panel,
          dialBackgroundColor: panelRaised,
          dialHandColor: cyan,
          hourMinuteColor: cyan.withValues(alpha: .12),
          dayPeriodColor: magenta.withValues(alpha: .12),
        ),
      ),
      child: child!,
    ),
  );
  return selected == null ? null : selected.hour * 60 + selected.minute;
}

class _TimeSelector extends StatelessWidget {
  const _TimeSelector({
    required this.label,
    required this.minutes,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int minutes;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withValues(alpha: .6)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    child: Row(
      children: [
        Text(label, style: microStyle.copyWith(color: color)),
        const Spacer(),
        Text(
          RiskWindow.formatMinutes(minutes),
          style: displayFont(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.edit_outlined, size: 16),
      ],
    ),
  );
}

class _FeedbackToggle extends StatelessWidget {
  const _FeedbackToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color.withValues(alpha: value ? .1 : .035),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: color.withValues(alpha: value ? .55 : .16)),
    ),
    child: SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 11),
      secondary: Icon(icon, color: value ? color : muted, size: 20),
      title: Text(
        title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 9.5, color: value ? color : muted),
      ),
      value: value,
      activeThumbColor: color,
      onChanged: onChanged,
    ),
  );
}

class _SoundEffectOption extends StatelessWidget {
  const _SoundEffectOption({
    required this.effect,
    required this.selected,
    required this.onTap,
  });

  final FeedbackSoundEffect effect;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: selected
            ? purple.withValues(alpha: .16)
            : Colors.white.withValues(alpha: .025),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? purple.withValues(alpha: .75)
              : muted.withValues(alpha: .18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? purple : muted,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  effect.label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  effect.description,
                  style: const TextStyle(color: muted, fontSize: 9.5),
                ),
              ],
            ),
          ),
          Icon(Icons.play_arrow_rounded, color: selected ? cyan : muted),
        ],
      ),
    ),
  );
}
