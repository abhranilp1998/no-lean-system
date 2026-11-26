import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/no_lean_visuals.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../companion/presentation/companion_common.dart';
import '../domain/post_relapse_summary.dart';
import 'dose_safety_cards.dart';
import 'quick_breath_card.dart';

const _amber = Colors.amber;

/// The content of the lock screen shown after a relapse log. Everything on it
/// is computed offline from the user's own event log and works while locked.
class PostRelapseLockBody extends ConsumerWidget {
  const PostRelapseLockBody({
    required this.summary,
    required this.now,
    super.key,
  });

  final PostRelapseSummary summary;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visuals = NoLeanVisuals.of(context);
    final soft = visuals.secondaryTextColor;
    final contactName = ref.watch(trustedContactProvider).valueOrNull?.name;
    final steps = nextTwentyFourHours(
      now: now,
      mixingRisk: summary.mixingRisk,
      contactName: contactName,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: StatusPill(label: 'RELAPSE LOGGED // ENTRY SAVED', color: red),
        ),
        const SizedBox(height: 14),
        _Hero(now: now, soft: soft),
        const SizedBox(height: 12),
        _StreakCard(summary: summary, soft: soft),
        if (summary.mixingRisk) ...[
          const SizedBox(height: 12),
          _MixingCard(soft: soft),
        ],
        if (summary.lowerTolerance) ...[
          const SizedBox(height: 12),
          _ToleranceCard(days: summary.previousDays, soft: soft),
        ],
        const SizedBox(height: 12),
        _NextDay(steps: steps, soft: soft),
        const SizedBox(height: 12),
        const QuickBreathCard(),
        const SizedBox(height: 12),
        _Encouragement(text: postRelapseEncouragement(summary.seed)),
        const SizedBox(height: 12),
        Text(
          'Need a person right now? Use OPEN SOS to reach your own SOS '
          'contact, or go to a doctor or a hospital. SOS and craving '
          'logging stay open without unlocking.',
          key: const ValueKey('post-relapse-footnote'),
          style: TextStyle(color: soft, fontSize: 11, height: 1.5),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.now, required this.soft});
  final DateTime now;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: red,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, color: red, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'LOCKED AFTER RELAPSE LOG',
                  style: eyebrowStyle.copyWith(color: red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            postRelapseGreeting(now),
            key: const ValueKey('post-relapse-greeting'),
            style: TextStyle(color: soft, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'That took honesty.',
            style: displayFont(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Thank you for telling the truth. Your entry is saved. The app '
            'is locked so your next step is a deliberate one, not a verdict.',
            style: TextStyle(color: soft, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.summary, required this.soft});
  final PostRelapseSummary summary;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final String eyebrow;
    final String headline;
    final String detail;
    if (s.timerKept) {
      eyebrow = 'YOUR STREAK IS INTACT';
      headline = '${s.previousDays}';
      detail =
          'Your lean clean timer was not reset by this entry. Keep the '
          'safety checks in mind.';
    } else if (s.hasStreak) {
      eyebrow = 'WHAT YOU BUILT';
      headline = '${s.previousDays}';
      detail =
          '${s.previousDays} ${s.previousDays == 1 ? 'day' : 'days'} still '
          'count. They happened, and one slip cannot delete them.';
    } else {
      eyebrow = 'DAY ONE, AGAIN';
      headline = '0';
      detail = s.bestDays > 0
          ? 'Your clean time starts again now. You have done '
                '${s.bestDays} ${s.bestDays == 1 ? 'day' : 'days'} before, '
                'so you know you can.'
          : 'Your clean time starts again now. Every honest log makes your '
                'plan smarter.';
    }
    final ratio = s.bestDays <= 0
        ? 0.0
        : (s.previousDays / s.bestDays).clamp(0.0, 1.0);
    final isBest = s.hasStreak && s.previousDays >= s.bestDays;
    return GlassCard(
      key: const ValueKey('post-relapse-streak'),
      accent: cyan,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: eyebrowStyle.copyWith(color: cyan)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                headline,
                key: const ValueKey('post-relapse-days'),
                style: displayFont(
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  color: cyan,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Text(
                  s.previousDays == 1 ? 'DAY' : 'DAYS',
                  style: eyebrowStyle.copyWith(color: soft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            key: const ValueKey('post-relapse-streak-detail'),
            style: TextStyle(color: soft, fontSize: 12.5, height: 1.5),
          ),
          if (s.bestDays > 0) ...[
            const SizedBox(height: 12),
            Semantics(
              label: 'This run ${s.previousDays} days, best ${s.bestDays} days',
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    color: cyan,
                    backgroundColor: cyan.withValues(alpha: .14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isBest ? 'THIS WAS YOUR BEST RUN' : 'THIS RUN',
                    style: microStyle.copyWith(color: soft),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'BEST: ${s.bestDays}D',
                  key: const ValueKey('post-relapse-best'),
                  style: microStyle.copyWith(color: soft),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WarnCard extends StatelessWidget {
  const _WarnCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.soft,
    this.extra,
  });
  final Key cardKey;
  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final Color soft;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: cardKey,
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: eyebrowStyle.copyWith(color: color)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(color: soft, fontSize: 12.5, height: 1.5),
          ),
          if (extra != null) ...[const SizedBox(height: 12), extra!],
        ],
      ),
    );
  }
}

class _MixingCard extends StatelessWidget {
  const _MixingCard({required this.soft});
  final Color soft;

  @override
  Widget build(BuildContext context) => _WarnCard(
    cardKey: const ValueKey('post-relapse-mixing'),
    icon: Icons.report_gmailerrorred,
    color: red,
    soft: soft,
    title: 'MIXING RISK // NEXT 24 HOURS',
    body:
        'A sedative or alcohol was logged in the last 24 hours. Together '
        'with lean they can slow your breathing, and you may not notice it '
        'happening. Take nothing more tonight, sleep on your side, and have '
        'someone check on you. If a person cannot be woken or is breathing '
        'slowly, get them to a doctor or a hospital now.',
    extra: const MixingSafetyNetCard(),
  );
}

class _ToleranceCard extends StatelessWidget {
  const _ToleranceCard({required this.days, required this.soft});
  final int days;
  final Color soft;

  @override
  Widget build(BuildContext context) => _WarnCard(
    cardKey: const ValueKey('post-relapse-tolerance'),
    icon: Icons.trending_down,
    color: _amber,
    soft: soft,
    title: 'LOWER TOLERANCE NOW',
    body:
        'After $days clean ${days == 1 ? 'day' : 'days'} your body has '
        'lost tolerance. What felt normal before can hit far harder than '
        'you expect, and that is when slips turn dangerous. It is a good '
        'reason to wait, and a better reason not to be alone.',
  );
}

class _NextDay extends StatelessWidget {
  const _NextDay({required this.steps, required this.soft});
  final List<NextStep> steps;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      key: const ValueKey('post-relapse-next-24'),
      accent: purple,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THE NEXT 24 HOURS',
            style: eyebrowStyle.copyWith(color: purple),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              step: steps[i],
              last: i == steps.length - 1,
              soft: soft,
              number: i + 1,
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.last,
    required this.soft,
    required this.number,
  });
  final NextStep step;
  final bool last;
  final Color soft;
  final int number;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${step.when}. ${step.title}. ${step.body}',
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: purple),
                      ),
                      child: Text(
                        '$number',
                        style: const TextStyle(
                          color: purple,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (!last)
                      Expanded(
                        child: Container(
                          width: 1,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: purple.withValues(alpha: .35),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: last ? 10 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.when,
                        style: microStyle.copyWith(
                          color: purple,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        step.body,
                        style: TextStyle(
                          color: soft,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Encouragement extends StatelessWidget {
  const _Encouragement({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.format_quote, color: toxic, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              key: const ValueKey('post-relapse-encouragement'),
              style: const TextStyle(
                color: toxic,
                fontSize: 14,
                height: 1.45,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
