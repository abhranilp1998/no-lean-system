import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
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
