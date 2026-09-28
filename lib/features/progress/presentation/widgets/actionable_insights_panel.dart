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
    super.key,
  });

  final List<PatternActionInsight> insights;
  final ValueChanged<PatternActionKind> onAction;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < insights.length; index++) ...[
        _PatternActionCard(
          insight: insights[index],
          primary: index == 0,
          onTap: () => onAction(insights[index].action),
        ),
        if (index != insights.length - 1) const SizedBox(height: 9),
      ],
    ],
  );
}

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
  });

  final PatternActionInsight insight;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = primary ? magenta : cyan;
    return GlassCard(
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
