import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../emergency/presentation/emergency_screen.dart';

import '../../recovery/application/recovery_provider.dart';
import '../data/symptom_checkin_store.dart';
import '../domain/withdrawal_guide.dart';

class WithdrawalGuideScreen extends ConsumerStatefulWidget {
  const WithdrawalGuideScreen({super.key, this.cleanOverride});

  /// For tests.
  final Duration? cleanOverride;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const WithdrawalGuideScreen()));

  @override
  ConsumerState<WithdrawalGuideScreen> createState() => _State();
}

class _State extends ConsumerState<WithdrawalGuideScreen> {
  final Map<Symptom, int> _picked = {};
  List<SymptomCheckIn> _history = [];
  SymptomCheckIn? _latest;

  @override
  void initState() {
    super.initState();
    ref.read(symptomCheckInStoreProvider).load().then((h) {
      if (!mounted) return;
      setState(() {
        _history = h;
        _latest = h.isEmpty ? null : h.first;
      });
    });
  }

  Future<void> _save() async {
    final c = SymptomCheckIn(at: DateTime.now(), severities: Map.of(_picked));
    await ref.read(symptomCheckInStoreProvider).add(c);
    setState(() {
      _latest = c;
      _history = [c, ..._history];
      _picked.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final clean =
        widget.cleanOverride ?? ref.watch(recoveryProvider).cleanDuration;
    final stage = stageFor(clean);
    final t = Theme.of(context).textTheme;
    final days = clean.inHours / 24;
    final logged = _latest?.severities.keys.toSet() ?? {};
    final tips = reliefFor(logged);

    Widget card(String title, List<Widget> children, {Color? color}) => Card(
      color: color,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );

    final helpButtons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          key: const Key('open-sos'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen())),
          icon: const Icon(Icons.sos),
          label: const Text('Open SOS / trusted contact'),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Withdrawal guide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          card('Where you are now', [
            Text(
              '${clean.inHours} hours (day ${days.floor() + 1}) · ${stage.title}',
              key: const Key('stage-title'),
              style: t.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('What\'s normal right now', style: t.labelLarge),
            Text(stage.normalNow),
            const SizedBox(height: 8),
            Text('Coming next', style: t.labelLarge),
            Text(stage.comingNext),
            const SizedBox(height: 8),
            Text(
              easesText(clean),
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ]),
          if (_latest?.hasRedFlag ?? false)
            card('Please get help today', [
              Text(redFlagText),
              const SizedBox(height: 12),
              helpButtons,
            ], color: Colors.red.withValues(alpha: 0.18)),
          card('How are you feeling?', [
            const Text(
              'Tap what you have. Tap again for stronger (mild → medium → severe). Saved only on this phone.',
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
                      _picked.containsKey(s)
                          ? '${s.label} · ${const ['', 'mild', 'medium', 'severe'][_picked[s]!]}'
                          : s.label,
                    ),
                    onSelected: (_) => setState(() {
                      final v = _picked[s] ?? 0;
                      if (v >= 3) {
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
                  '${_history.length} check-ins saved. Last: ${_history.first.severities.keys.map((e) => e.label).join(', ')}',
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
              Text(prescriptionNote, style: t.bodySmall),
              const SizedBox(height: 6),
              Text(
                notMedicalAdvice,
                style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ]),
          card('Do', [for (final d in generalDos) Text('✓  $d')]),
          card('Don\'t', [for (final d in generalDonts) Text('✗  $d')]),
          card('Get help', [
            const Text(
              'See a doctor or go to the nearest hospital for chest pain, seizure, confusion, fainting, blood in vomit or stool, slow breathing, or no fluids kept down for a day.',
            ),
            const SizedBox(height: 8),
            helpButtons,
          ]),
          card('Sources', [
            for (final s in guideSources)
              Text('• ${s.name}\n  ${s.url}', style: t.bodySmall),
            const SizedBox(height: 6),
            Text(notMedicalAdvice, style: t.bodySmall),
          ]),
        ],
      ),
    );
  }
}
