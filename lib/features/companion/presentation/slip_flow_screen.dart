import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/presentation/relapse_log_sheet.dart';
import '../domain/companion_engine.dart';
import '../domain/companion_messages.dart';
import '../domain/companion_state.dart';
import '../domain/substance_safety.dart';
import 'companion_common.dart';

/// "I used": no shame, tolerance warning, trigger, if-then plan.
class SlipFlowScreen extends ConsumerStatefulWidget {
  const SlipFlowScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const SlipFlowScreen()));

  @override
  ConsumerState<SlipFlowScreen> createState() => _SlipState();
}

class _SlipState extends ConsumerState<SlipFlowScreen> {
  String? _trigger;
  final _plan = TextEditingController();
  late final List<String> _lines;

  @override
  void initState() {
    super.initState();
    final r = ref.read(recoveryProvider);
    final c = CompanionContext(
      since: Duration.zero,
      now: DateTime.now(),
      recentSlip: true,
      bestDays: r.longestStreak,
    );
    final engine = CompanionEngine(r.companion, seed: DateTime.now().second);
    final picked = <String>{};
    _lines = [];
    for (var i = 0; i < 3; i++) {
      final m = engine.pick(MsgKind.lapse, c, exclude: {...picked, 'l03'});
      if (m == null) break;
      picked.add(m.id);
      _lines.add(render(m, c));
    }
  }

  @override
  void dispose() {
    _plan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final triggers = recovery.companion.triggers.isEmpty
        ? defaultTriggerOptions
        : recovery.companion.triggers;
    final notes = safetyNotesFor(recovery.companion, recentSlip: true);
    return Scaffold(
      appBar: AppBar(title: const Text('I slipped')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Thanks for being honest. Nothing here resets to zero, and nobody's judging.",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          for (final l in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('•  $l', style: const TextStyle(height: 1.35)),
            ),
          const SizedBox(height: 6),
          for (final n in notes) SafetyCard(n),
          const RedFlagsTile(),
          const SizedBox(height: 10),
          const Text(
            'What happened just before?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final t in triggers)
                ChoiceChip(
                  label: Text(t),
                  selected: _trigger == t,
                  onSelected: (v) => setState(() => _trigger = v ? t : null),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Next time that happens, I will...',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          TextField(
            controller: _plan,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'e.g. text my person and go for a walk',
            ),
          ),
          FilledButton(
            onPressed: () async {
              await recovery.updateCompanion(
                (s) => s.copyWith(
                  slips: [
                    SlipNote(
                      at: DateTime.now(),
                      trigger: _trigger ?? '',
                      ifThen: _plan.text.trim(),
                    ),
                    ...s.slips,
                  ].take(100).toList(),
                ),
              );
              if (!context.mounted) return;
              await showRelapseLogSheet(context, source: 'companion_slip');
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save and log it'),
          ),
          TextButton(
            onPressed: () => showReachOutSheet(context, ref, recovery),
            child: const Text('Tell my person'),
          ),
          if (recovery.companion.slips.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('YOUR PAST PLANS', style: eyebrowStyle),
            for (final s in recovery.companion.slips.take(5))
              if (s.ifThen.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    s.trigger.isEmpty
                        ? s.ifThen
                        : 'If ${s.trigger.toLowerCase()}: ${s.ifThen}',
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
