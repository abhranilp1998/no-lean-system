import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/craving_entry.dart';

Future<void> showCravingDialog(BuildContext context, WidgetRef ref) async {
  var intensity = 6.0;
  var trigger = 'After Work';
  final note = TextEditingController();
  const triggers = [
    'After Work',
    'Boredom',
    'Muscle Tension',
    'Loneliness',
    'Office Stress',
    'Habit',
    'Other',
  ];
  final entry = await showDialog<CravingEntry>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setState) => AppDialog(
        title: 'LOG THE SIGNAL',
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Intensity  /  ${intensity.round()} of 10',
                style: const TextStyle(
                  color: cyan,
                  fontWeight: FontWeight.w700,
                ),
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
                children: triggers
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
              TextField(
                controller: note,
                maxLines: 3,
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
                    // Close the route first. Persisting while this dialog is
                    // deactivating causes Flutter's inherited-element
                    // lifecycle assertion in debug mode.
                    Navigator.pop(
                      dialogContext,
                      CravingEntry(
                        intensity: intensity.round(),
                        trigger: trigger,
                        note: note.text.trim(),
                        createdAt: DateTime.now(),
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
      ),
    ),
  );
  note.dispose();
  if (entry != null && context.mounted) {
    await ref.read(recoveryProvider).recordCraving(entry);
  }
}
