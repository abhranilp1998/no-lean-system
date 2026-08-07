import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_dialog.dart';
import '../../recovery/application/recovery_provider.dart';

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
  }
}

Future<void> showPinSetup(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  if (!enabled) {
    await ref
        .read(recoveryProvider)
        .setSetting('requirePinAfterRelapse', false);
    return;
  }
  final controller = TextEditingController();
  final enteredPin = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: 'SET RELAPSE LOCK PIN',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: '4–6 digit PIN'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                if (controller.text.length < 4) return;
                // Return the value first. Persisting while the dialog route is
                // being deactivated triggers Flutter's inherited-element
                // lifecycle assertion in debug mode.
                Navigator.pop(dialogContext, controller.text);
              },
              child: const Text('ENABLE'),
            ),
          ),
        ],
      ),
    ),
  );
  if (enteredPin != null && context.mounted) {
    final recovery = ref.read(recoveryProvider);
    recovery.pin = enteredPin;
    await recovery.setSetting('requirePinAfterRelapse', true);
  }
  controller.dispose();
}
