import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_provider.dart';
import '../domain/high_risk_dates.dart';
import 'high_risk_dates_screen.dart';
import 'high_risk_plan_sheet.dart';

class HighRiskDatesCard extends ConsumerWidget {
  const HighRiskDatesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final upcoming = recovery.upcomingHighRiskDates(limit: 3);
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final weekday = recovery.worstWeekday;
    final dateFormat = DateFormat('EEE d MMM');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        key: const Key('high-risk-dates-card'),
        accent: cyan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('COMING UP', style: eyebrowStyle.copyWith(color: cyan)),
                const Spacer(),
                TextButton(
                  key: const Key('high-risk-dates-manage'),
                  onPressed: () => HighRiskDatesScreen.open(context),
                  child: const Text('MANAGE'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Dates that can be harder. A short plan, three days ahead.',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
            if (weekday != null) ...[
              const SizedBox(height: 8),
              Text(
                'Your logs point to ${weekdayNames[weekday]}s as a harder day.',
                key: const Key('high-risk-worst-weekday'),
                style: const TextStyle(fontSize: 11.5, color: muted),
              ),
            ],
            const SizedBox(height: 10),
            for (final item in upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_lead(item.daysUntil)} · ${dateFormat.format(item.date)}',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                          if (item.hasPlan)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                item.planNote!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: Key('high-risk-plan-${item.key}'),
                      onPressed: () =>
                          showHighRiskPlanSheet(context, ref, item),
                      child: Text(item.hasPlan ? 'SEE PLAN' : 'MAKE A PLAN'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _lead(int days) {
    if (days <= 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return 'In $days days';
  }
}
