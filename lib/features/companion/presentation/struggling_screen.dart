import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../../letters/presentation/future_letters_screen.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../withdrawal/data/symptom_checkin_store.dart';
import '../domain/companion_engine.dart';
import '../domain/idea_cards.dart';
import '../domain/substance_safety.dart';
import 'about_you_sheet.dart';
import 'companion_common.dart';
import 'urge_surf_screen.dart';

const _symptomChips = <String, String>{
  'aches': 'Body aches',
  'gut': 'Stomach / runs / sick',
  'sweats': 'Sweats / chills',
  'sleep': "Can't sleep",
  'anxiety': 'Anxious',
  'restless': 'Restless legs',
  'lowmood': 'Low',
};
const _redFlagChips = <String>[
  'Seizure or fit',
  'Confused / seeing things',
  'Chest pain',
  'Fainting',
  "Can't keep fluids down",
  'Thinking of ending my life',
];
const _moods = <String, String>{
  'low': 'Low',
  'anxious': 'Anxious',
  'irritable': 'Irritable',
  'numb': 'Numb',
  'okay': 'Okay',
  'good': 'Good',
};
const _cravingLabels = ['None', 'Mild', 'Strong', 'Overwhelming'];

/// "I'm struggling": three quick questions, then tailored right-now help.
class StrugglingScreen extends ConsumerStatefulWidget {
  const StrugglingScreen({super.key, this.nowOverride, this.seed});
  final DateTime? nowOverride;
  final int? seed;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const StrugglingScreen()));

  @override
  ConsumerState<StrugglingScreen> createState() => _StrugglingState();
}

class _StrugglingState extends ConsumerState<StrugglingScreen> {
  final Set<String> _symptoms = {};
  final Set<String> _flags = {};
  String? _mood;
  int _craving = 1;
  bool _showResults = false;
  String _name = '';
  CompanionView? _view;

  @override
  void initState() {
    super.initState();
    ref.read(symptomCheckInStoreProvider).loadPrefs().then((p) {
      if (mounted) setState(() => _name = p.name);
    });
  }

  Future<void> _results() async {
    final recovery = ref.read(recoveryProvider);
    final contact = await ref.read(trustedContactProvider.future);
    final c = contextFor(
      recovery,
      now: widget.nowOverride ?? DateTime.now(),
      symptoms: _symptoms,
      mood: _mood,
      craving: _craving,
      name: _name,
      contact: contact?.name ?? '',
    );
    final view = CompanionEngine(
      recovery.companion,
      seed: widget.seed ?? DateTime.now().millisecondsSinceEpoch,
    ).build(c);
    await recovery.updateCompanion((s) => s.markShown(view.shownIds, c.now));
    if (!mounted) return;
    setState(() {
      _view = view;
      _showResults = true;
    });
  }

  void _act(IdeaCard i) {
    final recovery = ref.read(recoveryProvider);
    switch (i.action) {
      case 'surf':
        UrgeSurfScreen.open(context);
      case 'reach':
        showReachOutSheet(context, ref, recovery);
      case 'letters':
        FutureLettersScreen.open(context);
      case 'sos':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text("I'm struggling"),
        actions: [
          IconButton(
            tooltip: 'About you',
            icon: const Icon(Icons.tune),
            onPressed: () => showAboutYouSheet(context, recovery),
          ),
        ],
      ),
      body: _showResults ? _resultsView(recovery) : _questions(recovery),
    );
  }

  Widget _questions(RecoveryController recovery) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        "You're not alone in this. Three quick taps and I'll pull up what helps right now.",
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 16),
      const Text(
        'What\'s hitting you?',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final e in _symptomChips.entries)
            FilterChip(
              label: Text(e.value),
              selected: _symptoms.contains(e.key),
              onSelected: (v) => setState(
                () => v ? _symptoms.add(e.key) : _symptoms.remove(e.key),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        'Any of these? (get help fast)',
        style: TextStyle(fontWeight: FontWeight.w700, color: red),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final f in _redFlagChips)
            FilterChip(
              side: BorderSide(color: red.withValues(alpha: .7)),
              label: Text(f),
              selectedColor: red.withValues(alpha: .3),
              selected: _flags.contains(f),
              onSelected: (v) =>
                  setState(() => v ? _flags.add(f) : _flags.remove(f)),
            ),
        ],
      ),
      if (_flags.isNotEmpty) ...[
        const SizedBox(height: 8),
        const RedFlagsTile(open: true),
      ],
      const SizedBox(height: 14),
      const Text('Mood', style: TextStyle(fontWeight: FontWeight.w700)),
      Wrap(
        spacing: 8,
        children: [
          for (final e in _moods.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _mood == e.key,
              onSelected: (v) => setState(() => _mood = v ? e.key : null),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Text(
        'Craving: ${_cravingLabels[_craving]}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      Slider(
        value: _craving.toDouble(),
        max: 3,
        divisions: 3,
        label: _cravingLabels[_craving],
        onChanged: (v) => setState(() => _craving = v.round()),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _results,
        child: const Text('Show me what helps'),
      ),
    ],
  );

  Widget _resultsView(RecoveryController recovery) {
    final view = _view!;
    final now = widget.nowOverride ?? DateTime.now();
    final c = contextFor(
      recovery,
      now: now,
      symptoms: _symptoms,
      mood: _mood,
      craving: _craving,
      name: _name,
    );
    void rate(String id, bool ok) {
      recovery.updateCompanion((s) => s.rate(id, wasHelpful: ok));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Noted. More like this.' : 'Got it. Fewer like that.',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    final notes = safetyNotesFor(recovery.companion, recentSlip: c.recentSlip);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          render(view.greeting, c),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (_flags.isNotEmpty) const RedFlagsTile(open: true),
        for (final n in notes) SafetyCard(n),
        if (view.messages.isNotEmpty)
          MessageCard(
            message: view.messages.first,
            text: render(view.messages.first, c),
            onRate: (ok) => rate(view.messages.first.id, ok),
          ),
        const SizedBox(height: 4),
        const Text('TRY ONE NOW', style: eyebrowStyle),
        const SizedBox(height: 8),
        for (final i in view.ideas)
          _IdeaTile(
            idea: i,
            onAct: () => _act(i),
            onRate: (ok) => rate(i.id, ok),
          ),
        for (final m in view.messages.skip(1))
          MessageCard(
            message: m,
            text: render(m, c),
            accent: purple,
            onRate: (ok) => rate(m.id, ok),
          ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => UrgeSurfScreen.open(context),
                icon: const Icon(Icons.waves),
                label: const Text('Ride the wave'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showReachOutSheet(context, ref, recovery),
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Message my person'),
              ),
            ),
          ],
        ),
        if (_flags.isEmpty) const RedFlagsTile(),
        TextButton(
          onPressed: () => setState(() => _showResults = false),
          child: const Text('Change my answers'),
        ),
      ],
    );
  }
}

class _IdeaTile extends StatelessWidget {
  const _IdeaTile({
    required this.idea,
    required this.onAct,
    required this.onRate,
  });
  final IdeaCard idea;
  final VoidCallback onAct;
  final void Function(bool) onRate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassCard(
      accent: toxic,
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  idea.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text('${idea.minutes} min', style: const TextStyle(color: muted)),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in idea.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 2, right: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(height: 1.3)),
                  Expanded(child: Text(s, style: const TextStyle(height: 1.3))),
                ],
              ),
            ),
          // 48dp tap targets, but the visible icon/text sits in the lower part of
          // each box so the card does not end in a band of empty space.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (idea.action != null)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    alignment: const Alignment(0, .5),
                  ),
                  onPressed: onAct,
                  child: const Text('Open'),
                ),
              IconButton(
                tooltip: 'Helped',
                padding: EdgeInsets.zero,
                alignment: const Alignment(0, .5),
                icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                onPressed: () => onRate(true),
              ),
              IconButton(
                tooltip: 'Not for me',
                padding: EdgeInsets.zero,
                alignment: const Alignment(0, .5),
                icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                onPressed: () => onRate(false),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
