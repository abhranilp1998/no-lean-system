import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/app_feedback.dart';
import '../../../../core/services/app_notice.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/no_lean_visuals.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../domain/recovery_insights.dart';
import '../../domain/verified_safety_briefs.dart';

class ActionableInsightsPanel extends StatelessWidget {
  const ActionableInsightsPanel({
    required this.insights,
    required this.onAction,
    this.onDismiss,
    this.dismissedCount = 0,
    this.onRestore,
    super.key,
  });

  final List<PatternActionInsight> insights;
  final ValueChanged<PatternActionKind> onAction;

  /// Dismiss until the evidence changes. Null hides the option.
  final ValueChanged<PatternActionInsight>? onDismiss;

  /// How many insights are currently hidden by a dismissal.
  final int dismissedCount;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < insights.length; index++) ...[
        _PatternActionCard(
          insight: insights[index],
          primary: index == 0,
          onTap: () => onAction(insights[index].action),
          onDismiss: onDismiss == null || !insights[index].dismissible
              ? null
              : () => onDismiss!(insights[index]),
        ),
        if (index != insights.length - 1) const SizedBox(height: 9),
      ],
      if (dismissedCount > 0 && onRestore != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('insights-restore'),
            onPressed: onRestore,
            child: Text(
              'SHOW $dismissedCount DISMISSED',
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
    ],
  );
}

/// Explains how an insight was computed and how much data backs it.
Future<void> showInsightWhySheet(
  BuildContext context,
  PatternActionInsight insight, {
  VoidCallback? onDismiss,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: panelRaised,
  isScrollControlled: true,
  builder: (sheetContext) {
    final confidence = insight.confidence;
    return SafeArea(
      child: SingleChildScrollView(
        key: ValueKey('insight-why-${insight.id}'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('WHY THIS INSIGHT', style: eyebrowStyle.copyWith(color: cyan)),
            const SizedBox(height: 8),
            Text(
              insight.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              insight.why.isEmpty ? insight.body : insight.why,
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text('EVIDENCE', style: microStyle.copyWith(color: muted)),
            const SizedBox(height: 3),
            Text(insight.evidence, style: const TextStyle(fontSize: 12)),
            if (confidence != null) ...[
              const SizedBox(height: 12),
              Text(
                'CONFIDENCE // ${confidence.label} (${insight.evidenceCount} DATA POINTS)',
                style: microStyle.copyWith(color: _confidenceColor(confidence)),
              ),
              const SizedBox(height: 3),
              Text(
                confidence.explanation,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              insight.dismissible
                  ? 'Dismissing hides this card until the facts behind it change, for example a new dose or a new log for this pattern. Nothing is deleted.'
                  : 'This card cannot be dismissed. It clears itself when the underlying signal passes.',
              style: const TextStyle(color: muted, fontSize: 11, height: 1.4),
            ),
            if (onDismiss != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('insight-dismiss'),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  onDismiss();
                },
                icon: const Icon(Icons.visibility_off_outlined, size: 16),
                label: const Text('DISMISS UNTIL THE EVIDENCE CHANGES'),
              ),
            ],
          ],
        ),
      ),
    );
  },
);

Color _confidenceColor(InsightConfidence confidence) => switch (confidence) {
  InsightConfidence.early => muted,
  InsightConfidence.moderate => cyan,
  InsightConfidence.strong => toxic,
};

class VerifiedRiskBriefs extends StatelessWidget {
  const VerifiedRiskBriefs({required this.insights, super.key});

  final List<VerifiedSafetyInsight> insights;

  @override
  Widget build(BuildContext context) {
    final matched = insights.where((insight) => insight.logMatched).length;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            matched == 0
                ? 'NO SPECIFIC LOG MATCH // BASELINE INTEL REMAINS AVAILABLE'
                : '$matched OF ${insights.length} BRIEFS MATCH LIVE LOG SIGNALS',
            style: microStyle.copyWith(
              color: matched == 0 ? muted : cyan,
              fontSize: 8.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < insights.length; index++) ...[
          _SafetyBriefCard(
            insight: insights[index],
            accent: switch (insights[index].brief.kind) {
              VerifiedSafetyBriefKind.depressantMixing => red,
              VerifiedSafetyBriefKind.reducedTolerance => magenta,
              VerifiedSafetyBriefKind.counterfeitPills => purple,
              VerifiedSafetyBriefKind.overdoseResponse => cyan,
            },
          ),
          if (index != insights.length - 1) const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const Text(
          'VERIFIED GUIDANCE // GENERAL SAFETY INFORMATION, NOT A DIAGNOSIS',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 8.5, letterSpacing: .45),
        ),
      ],
    );
  }
}

class _PatternActionCard extends StatelessWidget {
  const _PatternActionCard({
    required this.insight,
    required this.primary,
    required this.onTap,
    this.onDismiss,
  });

  final PatternActionInsight insight;
  final bool primary;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final accent = !insight.dismissible && insight.id == 'high-need'
        ? red
        : primary
        ? magenta
        : cyan;
    final confidence = insight.confidence;
    return GlassCard(
      key: ValueKey('insight-${insight.id}'),
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                primary ? Icons.bolt : Icons.analytics_outlined,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  insight.title,
                  style: microStyle.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            insight.body,
            style: const TextStyle(fontSize: 11.5, height: 1.45),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (confidence != null)
                Container(
                  key: ValueKey('insight-confidence-${insight.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: _confidenceColor(confidence)),
                  ),
                  child: Text(
                    confidence.label,
                    style: microStyle.copyWith(
                      fontSize: 8,
                      color: _confidenceColor(confidence),
                    ),
                  ),
                ),
              const Spacer(),
              TextButton(
                key: ValueKey('insight-why-button-${insight.id}'),
                onPressed: () =>
                    showInsightWhySheet(context, insight, onDismiss: onDismiss),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('WHY?', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  insight.evidence,
                  style: microStyle.copyWith(fontSize: 8.5),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {
                  AppFeedback.tap();
                  onTap();
                },
                icon: const Icon(Icons.arrow_forward, size: 15),
                label: Text(insight.actionLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'NoLeanMono',
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SafetyBriefCard extends StatefulWidget {
  const _SafetyBriefCard({required this.insight, required this.accent});

  final VerifiedSafetyInsight insight;
  final Color accent;

  @override
  State<_SafetyBriefCard> createState() => _SafetyBriefCardState();
}

class _SafetyBriefCardState extends State<_SafetyBriefCard> {
  bool _expanded = false;

  VerifiedSafetyBrief get _brief => widget.insight.brief;

  Future<void> _openSource() async {
    AppFeedback.tap();
    final opened = await launchUrl(
      Uri.parse(_brief.sourceUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      AppNotice.show(
        context,
        'SOURCE COULD NOT BE OPENED ON THIS DEVICE.',
        type: AppNoticeType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.accent.withValues(alpha: .42)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              AppFeedback.selection();
              setState(() => _expanded = !_expanded);
            },
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 5, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: widget.accent,
                      size: 19,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _brief.title,
                            style: TextStyle(
                              color: widget.accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .55,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.insight.logMatched
                                ? 'LOG MATCH // LIVE'
                                : 'BASELINE INTEL',
                            style: microStyle.copyWith(
                              color: widget.insight.logMatched
                                  ? widget.accent
                                  : muted,
                              fontSize: 7.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      link: true,
                      label: 'Open source: ${_brief.sourceLabel}',
                      child: IconButton(
                        tooltip: _brief.sourceLabel,
                        onPressed: _openSource,
                        icon: Icon(
                          Icons.open_in_new_rounded,
                          color: widget.accent,
                          size: 18,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: visuals.motionDuration(const Duration(milliseconds: 190)),
            curve: Curves.easeOutCubic,
            child: !_expanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: widget.accent.withValues(alpha: .2)),
                        Text(
                          'WHY THIS APPEARED // ${widget.insight.evidence}',
                          style: TextStyle(
                            color: widget.insight.logMatched
                                ? widget.accent
                                : muted,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _brief.summary,
                          style: const TextStyle(fontSize: 11, height: 1.45),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'NEXT MOVE // ${_brief.nextMove}',
                          style: TextStyle(
                            color: widget.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _brief.sourceLabel,
                          style: microStyle.copyWith(fontSize: 8),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
