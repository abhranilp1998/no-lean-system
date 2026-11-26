import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../plans/presentation/plan_card.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/if_then_plan.dart';
import '../../recovery/domain/slip_review.dart';
import '../../recovery/domain/trigger_tags.dart';

/// Optional quick tags for a craving that was just logged: where, who with,
/// mood, cash on hand. Each tap saves on the spot; after three taps the
/// sheet closes itself. Skipping costs nothing.
Future<void> showTriggerTagsSheet(BuildContext context, String cravingId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: panel,
      builder: (_) => TriggerTagsSheet(cravingId: cravingId),
    );

class TriggerTagsSheet extends ConsumerStatefulWidget {
  const TriggerTagsSheet({
    required this.cravingId,
    this.closeDelay = const Duration(milliseconds: 450),
    super.key,
  });

  final String cravingId;

  /// A short beat so the third tap is seen before the sheet closes.
  final Duration closeDelay;

  @override
  ConsumerState<TriggerTagsSheet> createState() => _TriggerTagsSheetState();
}

class _TriggerTagsSheetState extends ConsumerState<TriggerTagsSheet> {
  TriggerTags _tags = const TriggerTags();
  bool _closing = false;

  Future<void> _set(TriggerTags next) async {
    if (_closing) return;
    setState(() => _tags = next);
    try {
      await ref
          .read(recoveryProvider)
          .recordTriggerTags(widget.cravingId, next);
    } catch (_) {
      // The craving is already logged; a missed tag is not worth a warning.
    }
    if (next.count >= triggerTagMaxTaps && mounted && !_closing) {
      _closing = true;
      await Future<void>.delayed(widget.closeDelay);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _chip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    required Color color,
    Key? key,
    IconData? icon,
  }) => ChoiceChip(
    key: key,
    visualDensity: VisualDensity.compact,
    avatar: icon == null ? null : Icon(icon, size: 16, color: color),
    label: Text(
      label,
      style: TextStyle(fontSize: 12, color: selected ? Colors.white : null),
    ),
    selected: selected,
    selectedColor: color.withValues(alpha: .25),
    side: BorderSide(color: selected ? color : muted.withValues(alpha: .45)),
    onSelected: (_) => onTap(),
  );

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final place = _tags.cleanPlace;
    final isZone = _tags.zoneId != null;
    final plans = plansForCraving(
      recovery.ifThenPlans,
      mood: _tags.mood,
      zoneId: _tags.zoneId,
    );
    final left = triggerTagMaxTaps - _tags.count;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const ValueKey('trigger-tags'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'CRAVING LOGGED',
                      style: eyebrowStyle.copyWith(color: magenta),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _tags.isEmpty
                          ? 'Want to tag it? Up to three taps, all optional.'
                          : left > 0
                          ? 'Thanks. $left more tap${left == 1 ? '' : 's'} if you like.'
                          : 'Tagged. Thank you.',
                      key: const ValueKey('trigger-tags-lead'),
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Your tags show what sets cravings off. They stay on '
                      'your phone.',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                    ),
                    if (plans.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      PlanCard(
                        key: const ValueKey('trigger-tags-plan'),
                        plans: plans,
                        heading: 'YOUR PLAN',
                        maxShown: 1,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('WHERE', style: eyebrowStyle.copyWith(color: magenta)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final zone in recovery.zones)
                          _chip(
                            zone.name,
                            key: ValueKey('tag-zone-${zone.id}'),
                            icon: Icons.place,
                            color: red,
                            selected: _tags.zoneId == zone.id,
                            onTap: () => _set(
                              _tags.zoneId == zone.id
                                  ? _tags.copyWith(clearPlace: true)
                                  : _tags.copyWith(
                                      place: zone.name,
                                      zoneId: zone.id,
                                    ),
                            ),
                          ),
                        for (final label in slipPlaceOptions)
                          if (!recovery.zones.any(
                            (z) => z.name.toLowerCase() == label.toLowerCase(),
                          ))
                            _chip(
                              label,
                              key: ValueKey('tag-place-$label'),
                              color: magenta,
                              selected: place == label && !isZone,
                              onTap: () => _set(
                                place == label && !isZone
                                    ? _tags.copyWith(clearPlace: true)
                                    : _tags.copyWith(place: label),
                              ),
                            ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('WHO WITH', style: eyebrowStyle.copyWith(color: cyan)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in slipWithOptions.entries)
                          _chip(
                            entry.value,
                            key: ValueKey('tag-with-${entry.key}'),
                            color: cyan,
                            selected: _tags.withWho == entry.key,
                            onTap: () => _set(
                              _tags.withWho == entry.key
                                  ? _tags.copyWith(clearWith: true)
                                  : _tags.copyWith(withWho: entry.key),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('MOOD', style: eyebrowStyle.copyWith(color: purple)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in triggerMoodOptions.entries)
                          _chip(
                            entry.value,
                            key: ValueKey('tag-mood-${entry.key}'),
                            color: purple,
                            selected: _tags.mood == entry.key,
                            onTap: () => _set(
                              _tags.mood == entry.key
                                  ? _tags.copyWith(clearMood: true)
                                  : _tags.copyWith(mood: entry.key),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'CASH ON HAND',
                      style: eyebrowStyle.copyWith(color: toxic),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final entry in triggerCashOptions.entries)
                          _chip(
                            entry.value,
                            key: ValueKey('tag-cash-${entry.key}'),
                            color: toxic,
                            selected: _tags.cash == entry.key,
                            onTap: () => _set(
                              _tags.cash == entry.key
                                  ? _tags.copyWith(clearCash: true)
                                  : _tags.copyWith(cash: entry.key),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            OutlinedButton(
              key: const ValueKey('trigger-tags-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_tags.isEmpty ? 'SKIP' : 'DONE'),
            ),
          ],
        ),
      ),
    );
  }
}
