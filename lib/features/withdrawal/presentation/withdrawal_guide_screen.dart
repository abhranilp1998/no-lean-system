import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../emergency/presentation/emergency_screen.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/recovery_event.dart';
import '../data/symptom_checkin_store.dart';
import '../domain/companion.dart';
import '../domain/withdrawal_guide.dart';
import '../domain/withdrawal_personal.dart';

class WithdrawalGuideScreen extends ConsumerStatefulWidget {
  const WithdrawalGuideScreen({
    super.key,
    this.cleanOverride,
    this.nowOverride,
    this.eventsOverride,
  });

  /// For tests.
  final Duration? cleanOverride;
  final DateTime? nowOverride;
  final List<RecoveryEvent>? eventsOverride;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const WithdrawalGuideScreen()));

  @override
  ConsumerState<WithdrawalGuideScreen> createState() => _State();
}

class _State extends ConsumerState<WithdrawalGuideScreen> {
  final Map<Symptom, int> _picked = {};
  List<SymptomCheckIn> _history = [];
  CompanionPrefs _prefs = const CompanionPrefs();
  bool _askAgain = false;

  @override
  void initState() {
    super.initState();
    final store = ref.read(symptomCheckInStoreProvider);
    Future.wait([store.load(), store.loadPrefs()]).then((r) {
      if (!mounted) return;
      setState(() {
        _history = r[0] as List<SymptomCheckIn>;
        _prefs = r[1] as CompanionPrefs;
      });
    });
  }

  Future<void> _save() async {
    final c = SymptomCheckIn(at: DateTime.now(), severities: Map.of(_picked));
    await ref.read(symptomCheckInStoreProvider).add(c);
    setState(() {
      _history = [c, ..._history];
      _picked.clear();
    });
  }

  Future<void> _setPrefs(CompanionPrefs p) async {
    setState(() => _prefs = p);
    await ref.read(symptomCheckInStoreProvider).savePrefs(p);
  }

  void _openSos() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen()));

  Future<void> _editText(
    String title,
    String initial,
    ValueChanged<String> done, {
    TextInputType? type,
  }) async {
    final c = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, keyboardType: type, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (v != null) done(v);
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final now = widget.nowOverride ?? DateTime.now();
    final cleanSince = widget.cleanOverride != null
        ? now.subtract(widget.cleanOverride!)
        : recovery.lastDose;
    final events = widget.eventsOverride ?? recovery.events;
    final latest = _history.isEmpty ? null : _history.first;
    final plan = buildPlan(
      events: events,
      cleanSince: cleanSince,
      now: now,
      riskWindow: recovery.riskWindow,
      checkIns: _history,
    );
    final t = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final h = plan.sinceLastUse.inHours;
    final logged = latest?.severities.keys.toSet() ?? {};
    final tips = reliefFor(logged);
    final move = nextMove(
      plan,
      latest,
      now,
      inRiskWindow: recovery.riskWindow.contains(now),
    );

    Widget card(
      String title,
      List<Widget> children, {
      Color? color,
      Key? key,
    }) => Card(
      key: key,
      color: color,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[
              Text(title, style: t.titleMedium),
              const SizedBox(height: 8),
            ],
            ...children,
          ],
        ),
      ),
    );

    Widget bullets(List<String> items, [String mark = '•']) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('$mark  $i'),
          ),
      ],
    );

    Widget section(
      String title,
      List<String> items, {
      String mark = '•',
      bool open = false,
    }) => ExpansionTile(
      initiallyExpanded: open,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(title, style: t.titleSmall),
      children: [
        Align(alignment: Alignment.centerLeft, child: bullets(items, mark)),
      ],
    );

    final sosButton = FilledButton.icon(
      key: const Key('open-sos'),
      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
      onPressed: _openSos,
      icon: const Icon(Icons.sos),
      label: const Text('Open SOS / trusted contact'),
    );

    // Timeline with "you are here".
    final c = plan.course;
    final total = c.acuteEndH.toDouble();
    Widget seg(int i, Color color, String label) => Expanded(
      flex: (kTimelineWeights[i] * 100).round(),
      child: Column(
        children: [
          Container(height: 10, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: t.labelSmall,
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
    final timeline = LayoutBuilder(
      builder: (ctx, box) {
        final w = box.maxWidth;
        final frac = timelineFraction(plan.sinceLastUse.inMinutes / 60, c);
        // Marker centre, kept 1px inside so the 2px line never clips.
        final x = (frac * w).clamp(1.0, w - 1);
        const labelW = 72.0;
        final paws = h >= c.acuteEndH;
        final labelLeft = (x - labelW / 2).clamp(0.0, w - labelW);
        return Stack(
          key: const Key('stage-bar'),
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 28),
              child: Row(
                children: [
                  seg(0, Colors.amber.shade300, 'Early\n0–${c.peakStartH}h'),
                  seg(
                    1,
                    Colors.deepOrange.shade400,
                    'Peak\n${c.peakStartH}–${c.peakEndH}h',
                  ),
                  seg(
                    2,
                    Colors.teal.shade300,
                    'Easing\nto day ${(total / 24).round()}',
                  ),
                ],
              ),
            ),
            Positioned(
              left: labelLeft,
              top: 0,
              width: labelW,
              child: Text(
                paws ? 'PAWS' : 'You',
                key: const Key('you-are-here'),
                textAlign: TextAlign.center,
                style: t.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Triangle centred exactly on the marker line.
            Positioned(
              key: const Key('you-triangle'),
              left: x - 6,
              top: 14,
              child: Icon(Icons.arrow_drop_down, size: 12, color: accent),
            ),
            Positioned(
              key: const Key('you-line'),
              left: x - 1,
              top: 24,
              child: Container(width: 2, height: 20, color: accent),
            ),
          ],
        );
      },
    );

    final showQuestion = !_prefs.asked || _askAgain;

    return Scaffold(
      appBar: AppBar(title: const Text('Withdrawal guide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          card('', [
            Text(
              greeting(now, _prefs.name),
              key: const Key('greeting'),
              style: t.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              acknowledgement(plan, now),
              style: t.titleMedium?.copyWith(color: accent),
            ),
            const SizedBox(height: 6),
            Text(empathy(plan, latest)),
            if (_prefs.name.isEmpty)
              TextButton(
                onPressed: () => _editText(
                  'What should I call you?',
                  '',
                  (v) => _setPrefs(_prefs.copyWith(name: v)),
                ),
                child: const Text('Add your name'),
              ),
          ]),
          if (plan.inRelapse)
            card('You used recently', [
              const Text(
                'No judgement. The clock now counts from your last logged use. '
                'Don\'t take more to "top up": your tolerance may be lower than you think. '
                'Withdrawal may return in 6–12 hours, often milder after a short slip.',
              ),
            ], color: Colors.amber.withValues(alpha: 0.12)),
          if (latest?.hasRedFlag ?? false)
            card(
              'Please see a doctor today',
              [Text(redFlagText), const SizedBox(height: 12), sosButton],
              color: Colors.red.withValues(alpha: 0.18),
              key: const Key('red-flag-card'),
            ),
          card('Your next move', [
            Text(move.title, key: const Key('next-move'), style: t.titleLarge),
            const SizedBox(height: 4),
            Text(move.detail),
          ], color: accent.withValues(alpha: 0.10)),
          card('Where you are', [
            Text(
              '${h}h since last use · ${plan.stage.title}',
              key: const Key('stage-title'),
              style: t.titleLarge,
            ),
            const SizedBox(height: 12),
            timeline,
            const SizedBox(height: 16),
            Text('What\'s normal right now', style: t.labelLarge),
            Text(plan.stage.normalNow),
            const SizedBox(height: 10),
            for (final f in plan.forecast) ...[
              Text(f.label, style: t.labelLarge),
              Text(f.text),
              const SizedBox(height: 6),
            ],
            if (plan.riskTonight != null) ...[
              const SizedBox(height: 4),
              Text(
                '⚠ ${plan.riskTonight!}',
                key: const Key('risk-tonight'),
                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
            if (plan.trendText != null) ...[
              const SizedBox(height: 6),
              Text('📈 ${plan.trendText!}', key: const Key('trend')),
            ],
            if (plan.noData)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Using typical ranges. Log doses (ml), slips and cravings and this gets personal to you.',
                ),
              ),
            section('Why this forecast', plan.reasons),
          ]),
          if (showQuestion)
            card('A quick question (you can change it anytime)', [
              const Text('Would you be comfortable seeing a doctor?'),
              _ComfortRow(
                keyPrefix: 'doctor',
                value: _prefs.doctor,
                onPick: (v) => _setPrefs(_prefs.copyWith(doctor: v)),
              ),
              const SizedBox(height: 8),
              const Text('Would you be comfortable calling a support line?'),
              _ComfortRow(
                keyPrefix: 'support',
                value: _prefs.supportLine,
                onPick: (v) {
                  _setPrefs(_prefs.copyWith(supportLine: v));
                  if (_prefs.asked) setState(() => _askAgain = false);
                },
              ),
            ], key: const Key('comfort-card')),
          if (_prefs.doctor == Comfort.yes)
            card('Seeing a doctor', [
              const Text(
                'A doctor can make this much easier. What to tell them:',
              ),
              const SizedBox(height: 6),
              bullets(doctorBrief(plan, latest)),
              const SizedBox(height: 6),
              Text(doctorAskAbout),
            ], key: const Key('doctor-card')),
          if (_prefs.supportLine == Comfort.yes)
            card('Your support line', [
              if (_prefs.supportNumber.isEmpty)
                const Text(
                  'Add a number you trust (a counsellor, clinic or line you chose).',
                )
              else
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri(scheme: 'tel', path: _prefs.supportNumber),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.phone),
                  label: Text('Call ${_prefs.supportNumber}'),
                ),
              TextButton(
                onPressed: () => _editText(
                  'Support line number',
                  _prefs.supportNumber,
                  (v) => _setPrefs(_prefs.copyWith(supportNumber: v)),
                  type: TextInputType.phone,
                ),
                child: Text(
                  _prefs.supportNumber.isEmpty ? 'Add number' : 'Edit number',
                ),
              ),
            ]),
          if (_prefs.doctor == Comfort.no || _prefs.supportLine == Comfort.no)
            card('Your way', [
              const Text(
                'Got it. We\'ll focus on self-care and the people you trust. '
                'Your trusted contact is one tap away in SOS.',
              ),
            ]),
          card('How are you feeling?', [
            const Text(
              'Tap what you have. Tap again for stronger (mild → medium → severe). '
              'Warning signs are just on or off. Saved only on this phone.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in Symptom.values)
                  FilterChip(
                    key: Key('sym-${s.name}'),
                    selected: _picked.containsKey(s),
                    selectedColor: s.isRedFlag ? Colors.red.shade300 : null,
                    label: Text(
                      _picked.containsKey(s) && !s.isRedFlag
                          ? '${s.label} · ${const ['', 'mild', 'medium', 'severe'][_picked[s]!]}'
                          : s.label,
                    ),
                    onSelected: (_) => setState(() {
                      final v = _picked[s] ?? 0;
                      if (s.isRedFlag ? v >= 1 : v >= 3) {
                        _picked.remove(s);
                      } else {
                        _picked[s] = v + 1;
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('save-checkin'),
              onPressed: _picked.isEmpty ? null : _save,
              child: const Text('Save check-in'),
            ),
            if (_history.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_history.length} check-ins saved. Last: '
                  '${_history.first.severities.keys.map((e) => e.label).join(', ')}',
                ),
              ),
          ]),
          if (tips.isNotEmpty)
            card('What may help with what you logged', [
              for (final tip in tips) ...[
                Text(tip.title, style: t.labelLarge),
                Text(tip.body),
                const SizedBox(height: 8),
              ],
              Text(
                notMedicalAdvice,
                style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ]),
          card('Everything to know', [
            section('Hour by hour: 0 hours to 14 days', [
              for (final s in detailedStages)
                '${s.title}: ${s.items.join(' ')}',
            ]),
            section('Do', generalDos, mark: '✓'),
            section('Don\'t', generalDonts, mark: '✗'),
            for (final s in infoSections) section(s.title, s.items),
            const SizedBox(height: 8),
            sosButton,
            const SizedBox(height: 8),
            Text(notMedicalAdvice, style: t.bodySmall),
          ]),
          card('Sources', [
            for (final s in guideSources)
              Text('• ${s.name}\n  ${s.url}', style: t.bodySmall),
          ]),
          card('Settings', [
            TextButton(
              onPressed: () => _editText(
                'What should I call you?',
                _prefs.name,
                (v) => _setPrefs(_prefs.copyWith(name: v)),
              ),
              child: Text(
                _prefs.name.isEmpty
                    ? 'Add your name'
                    : 'Change name (${_prefs.name})',
              ),
            ),
            TextButton(
              key: const Key('ask-again'),
              onPressed: () => setState(() => _askAgain = true),
              child: const Text('Change doctor / support line answers'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ComfortRow extends StatelessWidget {
  const _ComfortRow({
    required this.keyPrefix,
    required this.value,
    required this.onPick,
  });
  final String keyPrefix;
  final Comfort value;
  final ValueChanged<Comfort> onPick;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    children: [
      for (final (c, label) in const [
        (Comfort.yes, 'Yes'),
        (Comfort.later, 'Maybe later'),
        (Comfort.no, 'No'),
      ])
        ChoiceChip(
          key: Key('$keyPrefix-${c.name}'),
          label: Text(label),
          selected: value == c,
          onSelected: (_) => onPick(c),
        ),
    ],
  );
}
