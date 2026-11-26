import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/domain/recovery_event.dart';
import '../../recovery/domain/trigger_pattern.dart';

/// What the user's own craving tags have in common, or a gentle note about
/// how many more tags it needs. Takes no space until they have tagged one.
class TriggerPatternCard extends StatelessWidget {
  const TriggerPatternCard({required this.events, this.now, super.key});

  final List<RecoveryEvent> events;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final status = computeTriggerPatternStatus(events, now: now);
    if (status.tagged == 0) return const SizedBox.shrink();
    final pattern = status.pattern;
    return GlassCard(
      key: const ValueKey('trigger-pattern-card'),
      accent: pattern == null ? muted : purple,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR PATTERN',
            style: eyebrowStyle.copyWith(
              color: pattern == null ? muted : purple,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            pattern?.sentence ??
                (status.stillNeeded > 0
                    ? 'Tag ${status.stillNeeded} more '
                          'craving${status.stillNeeded == 1 ? '' : 's'} and '
                          'this will show what usually sets them off.'
                    : 'Nothing stands out yet. That is fine: it only speaks '
                          'up when your tags clearly agree.'),
            key: const ValueKey('trigger-pattern-text'),
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
          if (pattern != null) ...[
            const SizedBox(height: 6),
            Text(pattern.evidence.toUpperCase(), style: microStyle),
          ],
        ],
      ),
    );
  }
}
