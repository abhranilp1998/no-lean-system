import 'data_fixes_v12.dart';
import 'recovery_event.dart';
import 'relapse_log_entry.dart';

/// Mixing alert: codeine/lean plus a benzo or alcohol logged within 24 hours
/// of each other, by when each one *happened* (`timestamp`), never by when it
/// was written down.
///
/// Derived entirely from fields every build has written (`relapseType`,
/// `note`, `quantity`), so old data and old backups work with no migration.

/// The two events are one mix when they are this close, either way round.
const mixingWindow = Duration(hours: 24);

/// A mix whose latest use is older than this is history, not tonight.
const mixingRecency = Duration(hours: 24);

final _benzoNames = RegExp(
  r'\b(alprazolam|xanax|alprax|diazepam|valium|lorazepam|ativan|clonazepam|'
  r'klonopin|rivotril|clonotril|etizolam|nitrazepam|nitrest|zolpidem|'
  r'benzo(?:s|diazepines?)?)\b',
  caseSensitive: false,
);

final _alcoholNames = RegExp(
  r'\b(alcohol|beer|whisk(?:e)?y|rum|vodka|wine|brandy|liquor|booze|daru|pegs?)\b',
  caseSensitive: false,
);

final _negatedBefore = RegExp(
  r"\b(no|not|never|without|instead of|skipped|avoided|didn'?t (have|take|buy|drink|use)|did not (have|take|buy|drink|use))\b(\s+\S+){0,2}\s*$",
  caseSensitive: false,
);

/// First un-negated match of [pattern] in [text], or null.
String? _mention(RegExp pattern, String text) {
  for (final m in pattern.allMatches(text)) {
    final clause = text
        .substring(0, m.start)
        .split(RegExp(r'[,.;!?]|\b(but|though|then)\b', caseSensitive: false))
        .last;
    if (!_negatedBefore.hasMatch(clause)) return m.group(0)!;
  }
  return null;
}

/// What one relapse event contains, for mixing purposes.
class SlipSubstances {
  const SlipSubstances({
    required this.codeine,
    this.benzo,
    this.alcohol = false,
  });

  /// Lean / codeine syrup.
  final bool codeine;

  /// Null = no benzo. Otherwise the name as logged ("alprazolam"), or
  /// "a benzo" when the log only says benzo.
  final String? benzo;
  final bool alcohol;

  bool get other => benzo != null || alcohol;
}

/// Reads one relapse event. Legacy events with no `relapseType` were always
/// lean in the app that wrote them, so they count as codeine.
SlipSubstances substancesOf(RecoveryEvent event) {
  final type = RelapseTypeLabel.fromName(event.metadata['relapseType']);
  final text =
      '${event.metadata['note'] ?? ''} '
      '${event.metadata['quantity'] ?? ''}';

  // A note on a benzo/alcohol/other entry can still name a codeine brand;
  // generic words like "lean" are too broad to count.
  final codeine =
      switch (type) {
        null ||
        RelapseType.fullLean ||
        RelapseType.partial ||
        RelapseType.leanPlusAlcohol => true,
        RelapseType.other || RelapseType.alcohol || RelapseType.benzo => false,
      } ||
      mentionsLeanBrand(text);

  final benzoName = _mention(_benzoNames, text);
  final benzo = type == RelapseType.benzo || benzoName != null
      ? _benzoLabel(benzoName)
      : null;
  final alcohol =
      type == RelapseType.alcohol ||
      type == RelapseType.leanPlusAlcohol ||
      _mention(_alcoholNames, text) != null;
  return SlipSubstances(codeine: codeine, benzo: benzo, alcohol: alcohol);
}

String _benzoLabel(String? name) {
  if (name == null) return 'a benzo';
  final lower = name.toLowerCase();
  return lower.startsWith('benzo') ? 'a benzo' : lower;
}

class MixingAlert {
  const MixingAlert({
    required this.substances,
    required this.eventIds,
    required this.latest,
    required this.today,
  });

  /// Names as logged, codeine first: ["codeine", "alprazolam"].
  final List<String> substances;

  /// Every relapse event that makes up this mix.
  final Set<String> eventIds;

  /// When the most recent of them happened.
  final DateTime latest;

  /// Whether they all happened today (device date).
  final bool today;

  /// 'You logged codeine + alprazolam today.'
  String get quote =>
      'You logged ${substances.join(' + ')} '
      '${today ? 'today' : 'in the last 24 hours'}.';
}

/// Finds a recent codeine + benzo/alcohol mix in the log, or null.
///
/// [involving], when given, limits this to mixes that include at least one of
/// those event ids, so saving an unrelated slip never re-raises an old mix.
/// A mix counts only while its latest use is within [mixingRecency] of [now].
MixingAlert? detectMixingAlert({
  required Iterable<RecoveryEvent> events,
  required DateTime now,
  Set<String>? involving,
}) {
  final slips = <(RecoveryEvent, SlipSubstances)>[
    for (final e in events)
      if (e.type == RecoveryEventType.relapse && !e.timestamp.isAfter(now))
        (e, substancesOf(e)),
  ]..sort((a, b) => a.$1.timestamp.compareTo(b.$1.timestamp));

  // Walk from the newest slip backwards for the latest qualifying pair.
  for (var i = slips.length - 1; i >= 0; i--) {
    final (anchor, anchorSub) = slips[i];
    if (now.difference(anchor.timestamp) > mixingRecency) break;
    final near = [
      for (final s in slips)
        if ((s.$1.timestamp.difference(anchor.timestamp)).abs() <= mixingWindow)
          s,
    ];
    final hasCodeine = near.any((s) => s.$2.codeine);
    final hasOther = near.any((s) => s.$2.other);
    // A single entry can be both (lean + alcohol); two entries can too.
    final mixed =
        near.any((s) => s.$2.codeine && s.$2.other) || (hasCodeine && hasOther);
    if (!mixed) continue;
    final ids = {for (final s in near) s.$1.id};
    if (involving != null && ids.intersection(involving).isEmpty) continue;
    final names = <String>[
      if (hasCodeine) 'codeine',
      ...{
        for (final s in near)
          if (s.$2.benzo != null) s.$2.benzo!,
      },
      if (near.any((s) => s.$2.alcohol)) 'alcohol',
    ];
    final latest = near
        .map((s) => s.$1.timestamp)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final sameDay = near.every(
      (s) => _sameDay(s.$1.timestamp.toLocal(), now.toLocal()),
    );
    return MixingAlert(
      substances: names,
      eventIds: ids,
      latest: latest,
      today: sameDay,
    );
  }
  return null;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
