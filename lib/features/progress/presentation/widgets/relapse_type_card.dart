import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../recovery/domain/dose_units.dart';
import '../../domain/dose_insights.dart';

/// Relapses split by type: how often, how much (ml kept apart from tablet
/// and drink counts) and what it actually cost.
class RelapseTypeCard extends StatelessWidget {
  const RelapseTypeCard({required this.stats, super.key});

  final List<RelapseTypeStats> stats;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const ValueKey('relapse-type-card'),
      accent: red,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BY RELAPSE TYPE', style: microStyle.copyWith(color: red)),
          const SizedBox(height: 10),
          if (stats.isEmpty)
            const Text(
              'No relapses logged. Keep it that way.',
              style: TextStyle(fontSize: 12, color: muted),
            )
          else
            for (final entry in stats) ...[
              _TypeRow(stats: entry),
              if (entry != stats.last)
                Divider(color: Colors.white.withValues(alpha: .06), height: 18),
            ],
          const SizedBox(height: 8),
          Text(
            'ML TOTALS USE THE ML SAVED WITH EACH ENTRY // TABLETS AND DRINKS ARE COUNTED SEPARATELY',
            style: microStyle.copyWith(fontSize: 8),
          ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.stats});

  final RelapseTypeStats stats;

  @override
  Widget build(BuildContext context) {
    final facts = <String>[
      '${stats.count}×',
      if (stats.volumeDoses > 0)
        '${formatMl(stats.totalMl)} total · avg ${formatMl(stats.averageMl!)}',
      for (final entry in stats.countTotals.entries)
        '${formatAmount(entry.value)} ${entry.key.labelFor(entry.value)}',
      if (stats.costedCount > 0) '${money(stats.realCost)} recorded',
      if (stats.last != null)
        'last ${DateFormat('d MMM').format(stats.last!.toLocal())}',
    ];
    return Semantics(
      container: true,
      label: '${stats.label}: ${facts.join(', ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stats.label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              facts.join('  //  '),
              key: ValueKey('relapse-type-${stats.type?.name ?? 'untyped'}'),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
