import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../letters/presentation/future_letters_screen.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../withdrawal/data/symptom_checkin_store.dart';
import '../../withdrawal/domain/withdrawal_personal.dart';
import '../domain/companion_engine.dart';
import '../domain/companion_messages.dart';
import '../domain/substance_safety.dart';
import 'about_you_sheet.dart';
import 'companion_common.dart';
import 'slip_flow_screen.dart';
import 'struggling_screen.dart';

/// Companion home: greeting, progress, permanent milestones, help.
class CompanionHubScreen extends ConsumerStatefulWidget {
  const CompanionHubScreen({super.key, this.nowOverride, this.seed});
  final DateTime? nowOverride;
  final int? seed;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const CompanionHubScreen()));

  @override
  ConsumerState<CompanionHubScreen> createState() => _HubState();
}

class _HubState extends ConsumerState<CompanionHubScreen> {
  String _name = '';
  String _contact = '';
  CompanionView? _view;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      ref.read(symptomCheckInStoreProvider).loadPrefs(),
      ref.read(trustedContactProvider.future),
    ]).then((r) {
      if (!mounted) return;
      _name = (r[0] as dynamic).name as String;
      _contact = (r[1] as dynamic)?.name as String? ?? '';
      _compose();
    });
  }

  DateTime get _now => widget.nowOverride ?? DateTime.now();

  Future<void> _compose() async {
    final recovery = ref.read(recoveryProvider);
    final c = contextFor(recovery, now: _now, name: _name, contact: _contact);
    final view = CompanionEngine(
      recovery.companion,
      seed: widget.seed ?? _now.millisecondsSinceEpoch,
    ).build(c);
    setState(() => _view = view);
    await recovery.updateCompanion((s) => s.markShown(view.shownIds, _now));
    if (!recovery.companion.triggersAsked && !_asked && mounted) {
      _asked = true;
      await showAboutYouSheet(context, recovery);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final view = _view;
    final c = contextFor(recovery, now: _now, name: _name, contact: _contact);
    final plan = buildPlan(
      events: recovery.events,
      cleanSince: recovery.lastDose,
      now: _now,
      riskWindow: recovery.riskWindow,
    );
    final h = c.since.inHours;
    final ease = c.easeInHours;
    final longTerm = plan.dose.spanDays >= 180 || c.since.inDays >= 14;
    void rate(CompanionMessage m, bool ok) {
      recovery.updateCompanion((s) => s.rate(m.id, wasHelpful: ok));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Noted. More like this.' : 'Got it. Fewer like that.',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Companion'),
        actions: [
          IconButton(
            tooltip: 'About you',
            icon: const Icon(Icons.tune),
            onPressed: () => showAboutYouSheet(context, recovery),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (view != null)
            Text(
              render(view.greeting, c),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(
                label: 'CLEAN',
                value: h < 72 ? '$h h' : '${c.since.inDays} d',
              ),
              _Stat(
                label: 'USUALLY EASES',
                value: ease == null ? 'Past peak' : 'in ~$ease h',
              ),
              _Stat(label: 'NOT SPENT', value: c.saved.isEmpty ? '-' : c.saved),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: magenta),
              onPressed: () => StrugglingScreen.open(context),
              icon: const Icon(Icons.favorite),
              label: const Text(
                "I'M STRUGGLING",
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showReachOutSheet(context, ref, recovery),
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('My person'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => FutureLettersScreen.open(context),
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Letters'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final n in safetyNotesFor(
            recovery.companion,
            recentSlip: c.recentSlip,
            events: recovery.events,
            now: _now,
          ))
            SafetyCard(n, urgent: n == mixingCheckIn),
          if (view != null)
            for (final m in view.messages)
              MessageCard(
                message: m,
                text: render(m, c),
                accent: m.kind == MsgKind.lapse ? magenta : cyan,
                onRate: (ok) => rate(m, ok),
              ),
          const SizedBox(height: 6),
          const Text('MILESTONES (YOURS TO KEEP)', style: eyebrowStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in milestoneHours.entries)
                Chip(
                  avatar: Icon(
                    recovery.bestCleanHours >= e.key
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: recovery.bestCleanHours >= e.key ? toxic : muted,
                  ),
                  label: Text(e.value),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Once earned, a milestone stays. A slip never takes it back.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          if (longTerm) ...[const SizedBox(height: 14), const _PawsCard()],
          const SizedBox(height: 14),
          if (recovery.companion.triggers.isNotEmpty)
            GlassCard(
              accent: purple,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('YOUR CRAVING TRIGGERS', style: eyebrowStyle),
                  const SizedBox(height: 6),
                  Text(recovery.companion.triggers.join(' · ')),
                  const SizedBox(height: 4),
                  const Text(
                    'Plan something for these times before they arrive.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          const RedFlagsTile(),
          TextButton.icon(
            onPressed: () => SlipFlowScreen.open(context),
            icon: const Icon(Icons.undo),
            label: const Text('I slipped (no judgement)'),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GlassCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: microStyle),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// After the first two weeks. SAMHSA Advisory "Protracted Withdrawal"
/// (SMA10-4554): symptoms vary, no agreed timeframe.
class _PawsCard extends StatelessWidget {
  const _PawsCard();

  @override
  Widget build(BuildContext context) => const GlassCard(
    accent: purple,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AFTER THE FIRST TWO WEEKS', style: eyebrowStyle),
        SizedBox(height: 6),
        Text(
          'After long daily use, some people get a slower second phase: low '
          'mood, nothing feeling fun, poor sleep, low energy, foggy thinking '
          'and cravings that come in waves. It can come and go for weeks to '
          'months, and some people feel clear for a month or two before a '
          'wave hits. It is a known part of recovery, not a sign it is not '
          'working. Waves usually get shorter and further apart.',
          style: TextStyle(height: 1.35),
        ),
        SizedBox(height: 6),
        Text(
          'What helps: same wake-up time, daylight and a walk, small planned '
          'good things even when they feel flat, people who do not use, and '
          'a plan for your trigger times. If low mood is heavy for weeks, see '
          'a doctor; treating it lowers relapse risk.',
          style: TextStyle(color: muted, height: 1.35),
        ),
      ],
    ),
  );
}
