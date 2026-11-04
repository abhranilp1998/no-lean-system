/// Pure-Dart message picker. Deterministic for a given seed so it is testable.
library;

import 'dart:math' as math;

import '../../withdrawal/domain/withdrawal_guide.dart';
import 'companion_messages.dart';
import 'companion_state.dart';
import 'idea_cards.dart';

String bandFor(Duration since) {
  final h = since.inHours;
  if (h < 12) return 'h0_12';
  if (h < 24) return 'h12_24';
  if (h < 48) return 'h24_48';
  if (h < 72) return 'h48_72';
  final d = since.inDays;
  if (d < 5) return 'd3_5';
  if (d < 7) return 'd5_7';
  if (d < 14) return 'd7_14';
  if (d < 30) return 'w2_4';
  if (d < 90) return 'm1_3';
  return 'm3plus';
}

String todFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return 'morning';
  if (h >= 11 && h < 17) return 'afternoon';
  if (h >= 17 && h < 22) return 'evening';
  return 'night';
}

String symptomTag(Symptom s) => switch (s) {
  Symptom.cramps || Symptom.diarrhoea || Symptom.vomiting => 'gut',
  Symptom.aches => 'aches',
  Symptom.sweats || Symptom.runnyNose => 'sweats',
  Symptom.sleep => 'sleep',
  Symptom.anxiety => 'anxiety',
  Symptom.cravings => 'cravings',
  Symptom.lowMood => 'lowmood',
  _ => 'any',
};

class CompanionContext {
  const CompanionContext({
    required this.since,
    required this.now,
    this.symptoms = const {},
    this.mood,
    this.craving = 0,
    this.recentSlip = false,
    this.name = '',
    this.bestDays = 0,
    this.saved = '',
    this.contact = '',
    this.easeInHours,
  });
  final Duration since;
  final DateTime now;
  final Set<String> symptoms;
  final String? mood;
  final int craving;
  final bool recentSlip;
  final String name;
  final int bestDays;
  final String saved;
  final String contact;
  final int? easeInHours;
}

class CompanionView {
  const CompanionView({
    required this.greeting,
    required this.messages,
    required this.ideas,
  });
  final CompanionMessage greeting;
  final List<CompanionMessage> messages;
  final List<IdeaCard> ideas;
  Iterable<String> get shownIds => [greeting.id, ...messages.map((m) => m.id)];
}

final _slot = RegExp(r'\{(\w+)\}');

/// Fills placeholders. Returns null when a needed value is missing.
String? fill(String text, CompanionContext c) {
  String? v(String key) => switch (key) {
    'name' => c.name.trim().isEmpty ? null : c.name.trim(),
    'hours' => '${c.since.inHours}',
    'days' => '${math.max(1, c.since.inDays)}',
    'easeIn' =>
      c.easeInHours == null || c.easeInHours! <= 0 ? null : '${c.easeInHours}',
    'best' => c.bestDays < 2 ? null : '${c.bestDays}',
    'saved' => c.saved.isEmpty ? null : c.saved,
    'contact' => c.contact.trim().isEmpty ? null : c.contact.trim(),
    _ => null,
  };
  var missing = false;
  final out = text.replaceAllMapped(_slot, (m) {
    final r = v(m[1]!);
    if (r == null) missing = true;
    return r ?? '';
  });
  return missing ? null : out;
}

/// Name is optional: drop ", {name}" style greetings gracefully.
String render(CompanionMessage m, CompanionContext c) =>
    fill(m.text, c) ??
    fill(
      m.text
          .replaceAll(', {name}', '')
          .replaceAll(' {name}', '')
          .replaceAll('{name}', ''),
      c,
    ) ??
    m.text.replaceAll(_slot, '');

bool _usable(CompanionMessage m, CompanionContext c) {
  final withoutName = m.text.replaceAll('{name}', '');
  return fill(withoutName, c) != null;
}

bool matches(CompanionMessage m, CompanionContext c, String band, String tod) {
  if (m.lapse != c.recentSlip && m.kind == MsgKind.lapse) return false;
  if (m.lapse && !c.recentSlip) return false;
  if (m.bands.isNotEmpty && !m.bands.contains(band)) return false;
  if (m.tods.isNotEmpty && !m.tods.contains(tod)) return false;
  if (m.symptoms.isNotEmpty && m.symptoms.intersection(c.symptoms).isEmpty) {
    return false;
  }
  if (m.moods.isNotEmpty && (c.mood == null || !m.moods.contains(c.mood))) {
    return false;
  }
  if (m.minCraving > c.craving) return false;
  return _usable(m, c);
}

class CompanionEngine {
  CompanionEngine(this.state, {int seed = 0}) : _rng = math.Random(seed);
  final CompanionState state;
  final math.Random _rng;

  bool _fresh(String id, DateTime now) {
    final last = state.shown[id];
    return last == null || now.difference(last) >= const Duration(days: 7);
  }

  double _weight(CompanionMessage m) {
    final up = state.helpful[m.id] ?? 0;
    final down = state.notHelpful[m.id] ?? 0;
    return (1 + m.specificity) * (1 + up * .5) / (1 + down * 1.5);
  }

  CompanionMessage? pick(
    MsgKind kind,
    CompanionContext c, {
    Set<String> exclude = const {},
  }) {
    final band = bandFor(c.since);
    final tod = todFor(c.now);
    final all = companionMessages
        .where((m) => m.kind == kind && !exclude.contains(m.id))
        .where((m) => matches(m, c, band, tod))
        .toList();
    if (all.isEmpty) return null;
    var pool = all.where((m) => _fresh(m.id, c.now)).toList();
    // Everything seen this week: fall back to the least recently shown.
    if (pool.isEmpty) {
      all.sort(
        (a, b) => (state.shown[a.id] ?? DateTime(2000)).compareTo(
          state.shown[b.id] ?? DateTime(2000),
        ),
      );
      pool = [all.first];
    }
    final total = pool.fold<double>(0, (s, m) => s + _weight(m));
    var r = _rng.nextDouble() * total;
    for (final m in pool) {
      r -= _weight(m);
      if (r <= 0) return m;
    }
    return pool.last;
  }

  CompanionView build(CompanionContext c) {
    final used = <String>{};
    CompanionMessage take(MsgKind k, [MsgKind fallback = MsgKind.together]) {
      final m = pick(k, c, exclude: used) ?? pick(fallback, c, exclude: used)!;
      used.add(m.id);
      return m;
    }

    final greeting = take(MsgKind.greet);
    final order = <MsgKind>[
      if (c.recentSlip) MsgKind.lapse,
      if (c.craving >= 2) MsgKind.craving,
      MsgKind.praise,
      if (c.since.inDays >= 14 && !c.recentSlip) MsgKind.paws,
      if (todFor(c.now) == 'night') MsgKind.night,
      MsgKind.normalise,
      MsgKind.together,
    ];
    final messages = [for (final k in order.take(4)) take(k)];
    return CompanionView(
      greeting: greeting,
      messages: messages,
      ideas: pickIdeas(c),
    );
  }

  List<IdeaCard> pickIdeas(CompanionContext c, {int count = 4}) {
    final tod = todFor(c.now);
    int score(IdeaCard i) {
      var s = 0;
      if (i.symptoms.intersection(c.symptoms).isNotEmpty) s += 3;
      if (c.craving >= 2 && i.category == IdeaCategory.craving) s += 4;
      if (c.craving >= 2 && i.action == 'surf') s += 3;
      if (c.craving >= 2 && i.action == 'reach') s += 2;
      if (c.mood == 'low' && i.category == IdeaCategory.reach) s += 2;
      s += (state.helpful[i.id] ?? 0) - 2 * (state.notHelpful[i.id] ?? 0);
      return s;
    }

    final usable =
        ideaCards
            .where((i) => i.tods.isEmpty || i.tods.contains(tod))
            .where((i) => i.minCraving <= math.max(c.craving, 0))
            .toList()
          ..shuffle(_rng);
    usable.sort((a, b) => score(b).compareTo(score(a)));
    final out = <IdeaCard>[];
    final cats = <IdeaCategory>{};
    for (final i in usable) {
      if (out.length >= count) break;
      if (cats.add(i.category)) out.add(i);
    }
    for (final i in usable) {
      if (out.length >= count) break;
      if (!out.contains(i)) out.add(i);
    }
    return out;
  }
}

/// Milestones that only add; a slip never removes one already reached.
const milestoneHours = <int, String>{
  24: '24 hours',
  72: '3 days',
  168: '1 week',
  336: '2 weeks',
  720: '30 days',
  2160: '90 days',
  4320: '180 days',
  8760: '1 year',
};
