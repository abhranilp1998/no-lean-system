import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../domain/recovery_insights.dart';

class InsightBreakdownCard extends StatelessWidget {
  const InsightBreakdownCard({
    required this.title,
    required this.emptyMessage,
    required this.entries,
    required this.accent,
    this.maxVisible,
    super.key,
  });

  final String title;
  final String emptyMessage;
  final List<InsightBreakdown> entries;
  final Color accent;
  final int? maxVisible;

  @override
  Widget build(BuildContext context) {
    final visibleEntries = maxVisible == null
        ? entries
        : entries.take(maxVisible!).toList();
    return GlassCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  boxShadow: [BoxShadow(color: accent, blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 8),
              Text(title, style: microStyle.copyWith(color: accent)),
              const Spacer(),
              Text(
                '${entries.fold<int>(0, (sum, entry) => sum + entry.count)} LOGS',
                style: microStyle.copyWith(color: muted, fontSize: 8.5),
              ),
            ],
          ),
          if (visibleEntries.isEmpty) ...[
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(fontSize: 11, color: muted, height: 1.4),
            ),
          ] else ...[
            const SizedBox(height: 14),
            for (var index = 0; index < visibleEntries.length; index++) ...[
              _BreakdownRow(entry: visibleEntries[index], accent: accent),
              if (index != visibleEntries.length - 1)
                const SizedBox(height: 11),
            ],
            if (visibleEntries.length < entries.length) ...[
              const SizedBox(height: 10),
              Text(
                '+${entries.length - visibleEntries.length} LOWER-FREQUENCY SIGNALS',
                style: microStyle.copyWith(color: muted, fontSize: 8.5),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.entry, required this.accent});

  final InsightBreakdown entry;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final percentage = (entry.ratio * 100).round();
    return Semantics(
      label:
          '${entry.label}: ${entry.count} logs, $percentage percent, average intensity ${entry.averageIntensity.toStringAsFixed(1)} out of 10',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AVG ${entry.averageIntensity.toStringAsFixed(1)}',
                style: microStyle.copyWith(color: muted, fontSize: 8.5),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 38,
                child: Text(
                  '$percentage%',
                  textAlign: TextAlign.right,
                  style: displayFont(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: entry.ratio.clamp(0, 1),
              minHeight: 4,
              backgroundColor: panelRaised,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
