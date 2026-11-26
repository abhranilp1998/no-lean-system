import 'recovery_event.dart';
import 'slip_review.dart';
import 'trigger_tags.dart';

/// Fewest tagged cravings before any pattern is claimed.
const minTaggedCravings = 6;

/// Fewest cravings that must share the whole pattern.
const minPatternMatches = 3;

/// Only tags from this far back count, so an old habit does not outvote a
/// recent one.
const triggerPatternLookback = Duration(days: 120);

/// A pattern the user's own tags support.
class TriggerPattern {
  const TriggerPattern({
    required this.factors,
    required this.matching,
    required this.tagged,
  });

  /// The shared tags, in reading order (mood, company, place, cash).
  final Map<TagDimension, String> factors;

  /// Tagged cravings that carry every factor.
  final int matching;

  /// Cravings with at least one tag in the lookback.
  final int tagged;

  double get share => tagged == 0 ? 0 : matching / tagged;

  /// "Most" only when it is more than half; otherwise "Many".
  bool get isMost => share > .5;

  /// "bored, alone and with cash on you".
  String get situation => _joinPhrases([
    for (final dim in _readingOrder)
      if (factors[dim] != null) _phrase(dim, factors[dim]!),
  ]);

  /// One warm sentence, e.g. "Most of your cravings come when you're bored
  /// and alone, with cash on you."
  String get sentence =>
      '${isMost ? 'Most' : 'Many'} of your cravings come when you\'re '
      '$situation.';

  /// The same situation in the user's own voice, to start an if-then plan
  /// ("I'm bored, alone and with cash on me"). They can rewrite it.
  String get ifSuggestion {
    final mine = situation
        .replaceAll('your partner', 'my partner')
        .replaceAll('on you', 'on me')
        .replaceAll('you get it from', 'I get it from');
    return "I'm $mine";
  }

  String get evidence =>
      '$matching of your $tagged tagged cravings match this.';

  /// Changes whenever the facts change (for "dismiss until it changes").
  String get evidenceKey =>
      '$matching:$tagged:${factors.entries.map((e) => '${e.key.name}=${e.value}').join(',')}';
}

/// How far the user is from a pattern, for a gentle nudge.
class TriggerPatternStatus {
  const TriggerPatternStatus({required this.tagged, this.pattern});

  final int tagged;
  final TriggerPattern? pattern;

  int get stillNeeded =>
      tagged >= minTaggedCravings ? 0 : minTaggedCravings - tagged;
}

const _readingOrder = [
  TagDimension.mood,
  TagDimension.withWho,
  TagDimension.place,
  TagDimension.cash,
];

String _phrase(TagDimension dim, String value) {
  switch (dim) {
    case TagDimension.mood:
      return switch (value) {
        'low' => 'feeling low',
        _ => value,
      };
    case TagDimension.withWho:
      return switch (value) {
        'alone' => 'alone',
        'friends' => 'with friends',
        'family' => 'with family or your partner',
        'work' => 'with people from work',
        'supplier' => 'around someone you get it from',
        _ => 'with $value',
      };
    case TagDimension.place:
      final lower = value.toLowerCase();
      return switch (lower) {
        'home' => 'at home',
        'work' => 'at work',
        'outside' => 'outside',
        'shop / bar' => 'at a shop or bar',
        _ => lower.startsWith('friend') ? "at a friend's place" : 'at $value',
      };
    case TagDimension.cash:
      return switch (value) {
        'none' => 'with no cash on you',
        'some' => 'with a little cash on you',
        'plenty' => 'with cash on you',
        _ => 'with cash on you',
      };
  }
}

String _joinPhrases(List<String> parts) {
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first;
  return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

String? _valueOf(TriggerTags tags, TagDimension dim) {
  switch (dim) {
    case TagDimension.place:
      return tags.cleanPlace;
    case TagDimension.withWho:
      return tags.withWho != null && slipWithOptions.containsKey(tags.withWho)
          ? tags.withWho
          : null;
    case TagDimension.mood:
      return tags.mood != null && triggerMoodOptions.containsKey(tags.mood)
          ? tags.mood
          : null;
    case TagDimension.cash:
      return tags.cash != null && triggerCashOptions.containsKey(tags.cash)
          ? tags.cash
          : null;
  }
}

/// Finds what the user's own tags most often have in common.
///
/// Needs [minTaggedCravings] tagged cravings and [minPatternMatches] that
/// share the whole pattern, so it never claims a pattern from a couple of
/// taps. It states a count, never a cause.
TriggerPatternStatus computeTriggerPatternStatus(
  List<RecoveryEvent> events, {
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(triggerPatternLookback);
  final rows = <Map<TagDimension, String>>[];
  for (final event in events) {
    if (event.type != RecoveryEventType.craving) continue;
    if (event.timestamp.isBefore(cutoff)) continue;
    final tags = triggerTagsOf(event);
    final row = <TagDimension, String>{
      for (final dim in TagDimension.values) dim: ?_valueOf(tags, dim),
    };
    if (row.isNotEmpty) rows.add(row);
  }
  if (rows.length < minTaggedCravings) {
    return TriggerPatternStatus(tagged: rows.length);
  }

  // Each question's most common answer, best first.
  final tops = <TagDimension, MapEntry<String, int>>{};
  for (final dim in TagDimension.values) {
    final counts = <String, int>{};
    for (final row in rows) {
      final v = row[dim];
      if (v != null) counts[v] = (counts[v] ?? 0) + 1;
    }
    if (counts.isEmpty) continue;
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    if (ranked.first.value >= minPatternMatches) {
      tops[dim] = ranked.first;
    }
  }
  final order = tops.keys.toList()
    ..sort((a, b) {
      final byCount = tops[b]!.value.compareTo(tops[a]!.value);
      return byCount != 0 ? byCount : a.index.compareTo(b.index);
    });

  int matches(Map<TagDimension, String> factors) => rows
      .where((row) => factors.entries.every((f) => row[f.key] == f.value))
      .length;

  // Grow the pattern one question at a time while at least a third of the
  // tagged cravings (and 3) still share all of it.
  final chosen = <TagDimension, String>{};
  var matching = 0;
  for (final dim in order) {
    final trial = {...chosen, dim: tops[dim]!.key};
    final count = matches(trial);
    if (count >= minPatternMatches && count * 3 >= rows.length) {
      chosen
        ..clear()
        ..addAll(trial);
      matching = count;
    }
  }
  if (chosen.isEmpty) return TriggerPatternStatus(tagged: rows.length);
  return TriggerPatternStatus(
    tagged: rows.length,
    pattern: TriggerPattern(
      factors: chosen,
      matching: matching,
      tagged: rows.length,
    ),
  );
}

TriggerPattern? computeTriggerPattern(
  List<RecoveryEvent> events, {
  DateTime? now,
}) => computeTriggerPatternStatus(events, now: now).pattern;
