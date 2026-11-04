import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../recovery/application/recovery_controller.dart';
import '../domain/companion_state.dart';
import '../domain/substance_safety.dart';
import 'companion_common.dart';

/// Asks what the user uses and what sets cravings off. Editable any time.
Future<void> showAboutYouSheet(
  BuildContext context,
  RecoveryController recovery,
) async {
  var s = recovery.companion;
  final substances = Set.of(s.substances);
  var heavy = s.heavyAlcohol;
  final triggers = List.of(s.triggers);
  final custom = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final options = {...defaultTriggerOptions, ...triggers}.toList();
        final preview = CompanionState(
          substances: substances,
          heavyAlcohol: heavy,
        );
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About you', style: Theme.of(ctx).textTheme.titleLarge),
                  const Text(
                    'Stays on this phone. It helps the app give you the right '
                    'advice.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'What have you been using? Pick all that apply.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final x in Substance.values)
                        FilterChip(
                          label: Text(x.label),
                          selected: substances.contains(x),
                          onSelected: (v) => set(
                            () => v ? substances.add(x) : substances.remove(x),
                          ),
                        ),
                    ],
                  ),
                  if (substances.contains(Substance.alcohol))
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('I drink most days, or a lot at once'),
                      value: heavy,
                      onChanged: (v) => set(() => heavy = v),
                    ),
                  if (preview.needsTaperWarning) const SafetyCard(taperWarning),
                  const SizedBox(height: 10),
                  const Text(
                    'When do cravings usually hit you?',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in options)
                        FilterChip(
                          label: Text(t),
                          selected: triggers.contains(t),
                          onSelected: (v) => set(
                            () => v ? triggers.add(t) : triggers.remove(t),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: custom,
                          maxLength: 60,
                          decoration: const InputDecoration(
                            hintText: 'Add your own',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          final v = custom.text.trim();
                          if (v.isEmpty || triggers.contains(v)) return;
                          set(() {
                            triggers.add(v);
                            custom.clear();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await recovery.updateCompanion(
                          (c) => c.copyWith(
                            substances: substances,
                            heavyAlcohol:
                                substances.contains(Substance.alcohol) && heavy,
                            triggers: triggers,
                            triggersAsked: true,
                          ),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
