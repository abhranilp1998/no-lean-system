import '../../../core/layout/tab_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_header.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../cravings/presentation/craving_dialog.dart';
import '../../dashboard/presentation/dashboard_dialogs.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/recovery_event.dart';
import '../../settings/presentation/settings_dialogs.dart';
import '../domain/money_series.dart';
import '../domain/recovery_insights.dart';
import '../domain/verified_safety_briefs.dart';
import 'widgets/actionable_insights_panel.dart';
import 'widgets/craving_timeline_card.dart';
import 'widgets/insight_breakdown_card.dart';
import 'widgets/milestone_tracker.dart';
import 'widgets/money_chart_card.dart';
import 'widgets/progress_heat_map.dart';
import 'widgets/recovery_summary_cards.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final timeline = chronologicalCravingSeries(recovery.cravings);
    final relapses = recovery.events
        .where((event) => event.type == RecoveryEventType.relapse)
        .toList();
    final signals = riskSignals(
      cravings: recovery.cravings,
      relapses: relapses,
    );
    final triggers = signalTriggerBreakdown(signals);
    final timeBands = signalTimeBreakdown(signals);
    final windowShare = riskWindowShare(signals, recovery.riskWindow);
    final weekly = weeklyRecoverySummary(
      cravings: recovery.cravings,
      sosSessions: recovery.sosSessions,
      cleanDays: recovery.cleanDays,
    );
    final sos = sosCompletionSummary(recovery.sosSessions);
    final actions = patternActionInsights(
      cravings: recovery.cravings,
      sosSessions: recovery.sosSessions,
      dailySpend: recovery.dailySpend,
      moneySaved: recovery.moneySaved,
      relapses: relapses,
      riskWindow: recovery.riskWindow,
    );
    final safetyInsights = verifiedSafetyInsights(
      events: recovery.events,
      cleanStreakDays: recovery.streak,
    );

    void runAction(PatternActionKind action) {
      switch (action) {
        case PatternActionKind.logCraving:
          showCravingDialog(context, ref);
          return;
        case PatternActionKind.openSos:
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen()));
          return;
        case PatternActionKind.editRiskWindow:
          showRiskWindowDialog(context, ref);
          return;
        case PatternActionKind.pledge:
          showPledgeDialog(context, ref);
          return;
      }
    }

    return TabListView(
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text('PROGRESS', style: eyebrowStyle.copyWith(color: purple)),
        const SizedBox(height: 7),
        Text(
          'Evidence beats vibes.',
          style: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        GlassCard(
          accent: purple,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CLEAN DAYS / LAST 30',
                style: microStyle.copyWith(color: purple),
              ),
              const SizedBox(height: 18),
              ProgressHeatMap(cleanDays: recovery.cleanDays),
              const SizedBox(height: 14),
              Row(
                children: [
                  const StatusPill(label: 'ACTIVE', color: toxic),
                  const SizedBox(width: 8),
                  Text(
                    '${recovery.streak} day current streak',
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MoneyChartCard(
          points: cumulativeMoneySeries(
            events: recovery.events,
            dailySpend: recovery.dailySpend,
            now: DateTime.now(),
          ),
          dailySpend: recovery.dailySpend,
          onSetSpend: () => showSpendDialog(context, ref),
        ),
        const SizedBox(height: 14),
        CravingTimelineCard(points: timeline),
        const SizedBox(height: 14),
        WeeklySummaryCard(summary: weekly),
        const SizedBox(height: 20),
        const _SectionLabel(
          glyph: '>>',
          label: 'NEXT MOVE // YOUR DATA',
          color: magenta,
        ),
        const SizedBox(height: 10),
        ActionableInsightsPanel(insights: actions, onAction: runAction),
        const SizedBox(height: 20),
        _SectionLabel(glyph: '⌁', label: 'PATTERN RECOGNITION', color: magenta),
        const SizedBox(height: 10),
        InsightBreakdownCard(
          title: 'TRIGGER SIGNATURES',
          emptyMessage:
              'Log a craving or tag a relapse to identify repeat trigger signatures.',
          entries: triggers,
          accent: magenta,
          maxVisible: 5,
          totalLabel: '${signals.length} SIGNALS',
        ),
        const SizedBox(height: 12),
        InsightBreakdownCard(
          title: 'TIME-OF-DAY EXPOSURE',
          emptyMessage: 'Time-band exposure will appear after your first log.',
          entries: timeBands,
          accent: cyan,
          totalLabel: '${signals.length} SIGNALS',
          footnote: windowShare.total == 0
              ? null
              : 'YOUR WINDOW ${recovery.riskWindow.label} // '
                    '${windowShare.inWindow} OF ${windowShare.total} '
                    '(${windowShare.percent}%)'
                    '${windowShare.total < minimumSignalsForPattern ? ' // LOW DATA' : ''}',
        ),
        const SizedBox(height: 12),
        SosCompletionCard(summary: sos),
        const SizedBox(height: 20),
        const _SectionLabel(
          glyph: '!!',
          label: 'VERIFIED RISK INTEL',
          color: red,
        ),
        const SizedBox(height: 10),
        VerifiedRiskBriefs(insights: safetyInsights),
        const SizedBox(height: 20),
        const _SectionLabel(
          glyph: '◇',
          label: 'MILESTONE TRACKER',
          color: muted,
        ),
        const SizedBox(height: 10),
        MilestoneTracker(currentStreak: recovery.streak),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.glyph,
    required this.label,
    required this.color,
  });

  final String glyph;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        glyph,
        style: displayFont(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      const SizedBox(width: 7),
      Text(label, style: eyebrowStyle.copyWith(color: color)),
      const SizedBox(width: 9),
      Expanded(child: Container(height: 1, color: color.withValues(alpha: .2))),
    ],
  );
}
