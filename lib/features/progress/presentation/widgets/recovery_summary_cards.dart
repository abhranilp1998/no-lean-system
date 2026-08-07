import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../domain/recovery_insights.dart';

class WeeklySummaryCard extends StatelessWidget {
  const WeeklySummaryCard({required this.summary, super.key});

  final WeeklyRecoverySummary summary;

  @override
  Widget build(BuildContext context) => GlassCard(
    accent: purple,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '// 7-DAY TELEMETRY',
              style: microStyle.copyWith(color: purple),
            ),
            const Spacer(),
            Text(
              '${_dayMonth(summary.periodStart)}—${_dayMonth(summary.periodEnd)}',
              style: microStyle.copyWith(color: muted, fontSize: 8.5),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final itemWidth = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _TelemetryCell(
                  width: itemWidth,
                  label: 'CRAVINGS',
                  value: '${summary.cravingCount}',
                  detail: summary.cravingCount == 0
                      ? 'NO SIGNALS'
                      : 'PEAK ${summary.peakIntensity}/10',
                  color: magenta,
                ),
                _TelemetryCell(
                  width: itemWidth,
                  label: 'AVG INTENSITY',
                  value: summary.cravingCount == 0
                      ? '—'
                      : summary.averageIntensity.toStringAsFixed(1),
                  detail: 'OUT OF 10',
                  color: cyan,
                ),
                _TelemetryCell(
                  width: itemWidth,
                  label: 'CLEAN MARKS',
                  value: '${summary.cleanDays}/7',
                  detail: 'USER CHECK-INS',
                  color: toxic,
                ),
                _TelemetryCell(
                  width: itemWidth,
                  label: 'SOS CLEARED',
                  value: '${summary.sosCompleted}/${summary.sosStarted}',
                  detail: summary.sosStarted == 0
                      ? 'NO ACTIVATIONS'
                      : '${(summary.sosCompletionRate * 100).round()}% COMPLETE',
                  color: red,
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class SosCompletionCard extends StatelessWidget {
  const SosCompletionCard({required this.summary, super.key});

  final SosCompletionSummary summary;

  @override
  Widget build(BuildContext context) {
    final percentage = (summary.completionRate * 100).round();
    return GlassCard(
      accent: red,
      child: Semantics(
        label: summary.started == 0
            ? 'No SOS sessions recorded.'
            : '${summary.completed} of ${summary.started} SOS sessions completed, $percentage percent.',
        child: Row(
          children: [
            SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: summary.completionRate,
                      strokeWidth: 5,
                      color: red,
                      backgroundColor: red.withValues(alpha: .12),
                    ),
                  ),
                  Text(
                    summary.started == 0 ? '—' : '$percentage%',
                    style: displayFont(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SOS COMPLETION LINK',
                    style: microStyle.copyWith(color: red),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    summary.started == 0
                        ? 'No override sessions recorded yet.'
                        : '${summary.completed} of ${summary.started} waves completed',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _sosDetail(summary),
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TelemetryCell extends StatelessWidget {
  const _TelemetryCell({
    required this.width,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    decoration: BoxDecoration(
      color: panelRaised.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: microStyle.copyWith(color: muted, fontSize: 8.5)),
        const SizedBox(height: 5),
        Text(
          value,
          style: displayFont(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: microStyle.copyWith(color: muted, fontSize: 7.8),
        ),
      ],
    ),
  );
}

String _sosDetail(SosCompletionSummary summary) {
  final average = summary.averageDuration;
  if (average == null) {
    return 'Complete the full protocol to establish a response baseline.';
  }
  final seconds = average.inSeconds;
  return 'Average completed protocol: ${seconds}s · last clear ${_relativeDate(summary.lastCompletedAt!)}';
}

String _relativeDate(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'today';
  if (difference == 1) return 'yesterday';
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}';
}

String _dayMonth(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}';
