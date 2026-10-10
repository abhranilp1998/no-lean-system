import '../../../core/layout/tab_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/services/save_action.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/craving_entry.dart';
import '../../recovery/domain/recovery_event.dart';

Future<void> showCravingDialog(BuildContext context, WidgetRef ref) async {
  final entry = await showDialog<CravingEntry>(
    context: context,
    builder: (dialogContext) => const _CravingDialog(),
  );
  if (entry != null && context.mounted) {
    if (!await saveAction(
      context,
      () => ref.read(recoveryProvider).recordCraving(entry),
    )) {
      return;
    }
    if (context.mounted) {
      AppNotice.show(
        context,
        'CRAVING LOGGED // RECHECK IN 15 MIN.',
        type: AppNoticeType.success,
      );
    }
  }
}

class _CravingDialog extends StatefulWidget {
  const _CravingDialog();

  @override
  State<_CravingDialog> createState() => _CravingDialogState();
}

class _CravingDialogState extends State<_CravingDialog> {
  var intensity = 6.0;
  var trigger = 'After Work';
  int? stress;
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'LOG THE SIGNAL',
      child: KeyboardSafeScroll(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Intensity  /  ${intensity.round()} of 10',
              style: const TextStyle(color: cyan, fontWeight: FontWeight.w700),
            ),
            Slider(
              value: intensity,
              min: 1,
              max: 10,
              divisions: 9,
              activeColor: intensity >= 8 ? red : cyan,
              onChanged: (value) => setState(() => intensity = value),
            ),
            const SizedBox(height: 4),
            const Text('TRIGGER', style: microStyle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: recoveryTriggerOptions
                  .map(
                    (item) => ChoiceChip(
                      label: Text(item, style: const TextStyle(fontSize: 10)),
                      selected: trigger == item,
                      selectedColor: magenta.withValues(alpha: .25),
                      onSelected: (_) => setState(() => trigger = item),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            StressPicker(
              keyPrefix: 'craving-stress',
              value: stress,
              onChanged: (value) => setState(() => stress = value),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              scrollPadding: KeyboardSafeScroll.fieldScrollPadding,
              decoration: const InputDecoration(
                labelText: 'What is actually happening?',
                hintText: 'Name the moment, not the story.',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    CravingEntry(
                      intensity: intensity.round(),
                      trigger: trigger,
                      note: note.text.trim(),
                      createdAt: DateTime.now(),
                      stress: stress,
                    ),
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: magenta),
                child: const Text('LOG IT'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Optional 1-5 stress rating; tapping the selected value clears it.
class StressPicker extends StatelessWidget {
  const StressPicker({
    required this.keyPrefix,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String keyPrefix;
  final int? value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  static const labels = ['CALM', 'LOW', 'MEDIUM', 'HIGH', 'MAX'];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'STRESS (OPTIONAL)${value == null ? '' : ' // ${labels[value! - 1]}'}',
        style: microStyle,
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        children: [
          for (var level = 1; level <= 5; level++)
            ChoiceChip(
              key: ValueKey('$keyPrefix-$level'),
              label: Text('$level'),
              selected: value == level,
              selectedColor: magenta.withValues(alpha: .3),
              onSelected: enabled
                  ? (_) => onChanged(value == level ? null : level)
                  : null,
            ),
        ],
      ),
    ],
  );
}

/// "How is it now?" 15 minutes after a craving. 0 means it passed.
Future<void> showCravingRecheckDialog(
  BuildContext context,
  WidgetRef ref,
  RecoveryEvent craving,
) async {
  final original = craving.metadata['intensity'] as int;
  final value = await showDialog<int>(
    context: context,
    builder: (_) => _RecheckDialog(original: original),
  );
  if (value == null || !context.mounted) return;
  if (!await saveAction(
    context,
    () => ref
        .read(recoveryProvider)
        .recordCravingCheck(cravingId: craving.id, intensity: value),
  )) {
    return;
  }
  if (!context.mounted) return;
  final outcome = cravingCheckOutcome(original, value);
  AppNotice.show(context, switch (outcome) {
    'gone' => 'RECHECK // IT PASSED. THAT IS THE WIN.',
    'eased' => 'RECHECK // $original -> $value. IT IS FADING.',
    'same' => 'RECHECK // STILL $value. STAY MOVING.',
    _ => 'RECHECK // $original -> $value. OPEN SOS NOW.',
  }, type: outcome == 'stronger' ? AppNoticeType.error : AppNoticeType.success);
}

class _RecheckDialog extends StatefulWidget {
  const _RecheckDialog({required this.original});

  final int original;

  @override
  State<_RecheckDialog> createState() => _RecheckDialogState();
}

class _RecheckDialogState extends State<_RecheckDialog> {
  late double value = widget.original.toDouble();

  @override
  Widget build(BuildContext context) => AppDialog(
    title: 'CRAVING RECHECK',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'It was ${widget.original}/10. How strong is it now?',
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 10),
        Text(
          value == 0 ? 'GONE' : 'Now  /  ${value.round()} of 10',
          style: const TextStyle(color: cyan, fontWeight: FontWeight.w700),
        ),
        Slider(
          key: const ValueKey('recheck-intensity'),
          value: value,
          max: 10,
          divisions: 10,
          activeColor: value > widget.original ? red : cyan,
          onChanged: (next) => setState(() => value = next),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('recheck-save'),
            onPressed: () => Navigator.pop(context, value.round()),
            style: FilledButton.styleFrom(backgroundColor: magenta),
            child: const Text('SAVE RECHECK'),
          ),
        ),
      ],
    ),
  );
}

/// In-app prompt for a craving that is due for its 15-minute recheck.
class CravingRecheckCard extends ConsumerWidget {
  const CravingRecheckCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final craving = ref.watch(recoveryProvider).pendingCravingCheck;
    if (craving == null) return const SizedBox.shrink();
    final minutes = DateTime.now().difference(craving.timestamp).inMinutes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: magenta.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('craving-recheck-card'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => showCravingRecheckDialog(context, ref, craving),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: magenta),
            ),
            child: Row(
              children: [
                const Icon(Icons.update, color: magenta),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RECHECK DUE',
                        style: eyebrowStyle.copyWith(color: magenta),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Craving ${craving.metadata['intensity']}/10, $minutes min ago. Rate it again.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: magenta),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
