import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../report/presentation/doctor_report_screen.dart';
import '../domain/weekly_recap.dart';

/// Builds the recap from the live recovery state. Everything stays on the
/// phone; the card only reads the user's own logs.
class WeeklyRecapSection extends ConsumerWidget {
  const WeeklyRecapSection({this.now, super.key});

  /// For tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final recap = computeWeeklyRecap(
      events: recovery.events,
      lastDose: recovery.lastDose,
      now: now ?? DateTime.now(),
      dailySpend: recovery.dailySpend,
      formatMoney: money,
    );
    return WeeklyRecapCard(
      recap: recap,
      onDoctorReport: () => DoctorReportScreen.open(context),
    );
  }
}

class WeeklyRecapCard extends StatelessWidget {
  const WeeklyRecapCard({required this.recap, this.onDoctorReport, super.key});

  final WeeklyRecap recap;
  final VoidCallback? onDoctorReport;

  @override
  Widget build(BuildContext context) {
    String d(DateTime t) => DateFormat('d MMM').format(t);
    return GlassCard(
      key: const ValueKey('weekly-recap-card'),
      accent: toxic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('YOUR WEEK', style: microStyle.copyWith(color: toxic)),
              const Spacer(),
              Text(
                '${d(recap.periodStart)} to ${d(recap.periodEnd)}',
                style: microStyle.copyWith(color: muted, fontSize: 8.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            recap.headline,
            key: const ValueKey('weekly-recap-headline'),
            style: displayFont(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Stat(
                label: 'CLEAN DAYS',
                value: '${recap.cleanDays}/${recap.daysCovered}',
                color: toxic,
              ),
              _Stat(
                label: 'CRAVINGS',
                value: '${recap.cravings}',
                color: magenta,
              ),
              _Stat(
                label: 'RODE OUT',
                value: '${recap.cravingsRiddenOut}',
                color: cyan,
              ),
              if (recap.slips > 0)
                _Stat(label: 'SLIPS', value: '${recap.slips}', color: red),
              if (recap.benzoOnlyEntries > 0)
                _Stat(
                  label: 'BENZO ONLY',
                  value: '${recap.benzoOnlyEntries}',
                  color: purple,
                ),
              if (recap.moneyKept != null)
                _Stat(
                  label: 'KEPT',
                  value: money(recap.moneyKept!),
                  color: toxic,
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in recap.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            key: const ValueKey('weekly-recap-next-step'),
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: toxic.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: toxic.withValues(alpha: .3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ONE NEXT STEP', style: microStyle.copyWith(color: toxic)),
                const SizedBox(height: 5),
                Text(
                  recap.nextStep,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          if (onDoctorReport != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('weekly-recap-doctor-report'),
                onPressed: onDoctorReport,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('Make a summary for my doctor'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 84),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: microStyle.copyWith(color: color, fontSize: 8.5)),
        const SizedBox(height: 3),
        Text(
          value,
          style: displayFont(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
