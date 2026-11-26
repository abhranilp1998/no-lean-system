import 'data_fixes_v12.dart';
import 'recovery_event.dart';
import 'relapse_log_entry.dart';

/// Each comparison window is this many calendar days, ending today.
const swapWatchWindowDays = 14;

/// After a dismiss, the card stays hidden for this long.
const swapWatchCooldown = Duration(days: 7);

/// Need at least this many lean days in the earlier window to call it a drop.
const swapWatchMinPreviousLeanDays = 2;

/// A lean drop counts when it is at least this many unique days, or at least
/// [swapWatchMinLeanDropRatio] of the earlier window (and at least one day).
const swapWatchMinLeanDropDays = 2;
const swapWatchMinLeanDropRatio = 0.30;

/// Another substance has to rise by at least this many unique days, and
/// end with at least this many days in the recent window.
const swapWatchMinOtherRiseDays = 2;

/// Preference keys. Optional; a missing key means "on" / never shown.
const swapWatchEnabledKey = 'swapWatchEnabled';
const swapWatchDismissedAtKey = 'swapWatchDismissedAt';
const swapWatchNotifiedAtKey = 'swapWatchNotifiedAt';

/// The substances this watch compares, in a stable display order.
enum WatchedSubstance { lean, benzo, alcohol, weed, other }

extension WatchedSubstanceLabel on WatchedSubstance {
  /// Short name used in the card ("Lean is down 70%").
  String get label => switch (this) {
    WatchedSubstance.lean => 'Lean',
    WatchedSubstance.benzo => 'Benzos',
    WatchedSubstance.alcohol => 'Alcohol',
    WatchedSubstance.weed => 'Weed',
    WatchedSubstance.other => 'Other',
  };
}

/// Unique use-days for one substance in the earlier and recent 14-day windows.
class SubstanceDayCounts {
  const SubstanceDayCounts({required this.previous, required this.recent});

  final int previous;
  final int recent;

  int get delta => recent - previous;

  /// Average days per week in a 14-day window, for the card wording.
  double get previousPerWeek => previous / 2;
  double get recentPerWeek => recent / 2;
}

/// A detected swap: lean days fell, and another substance's days rose.
class SwapWatchInsight {
  const SwapWatchInsight({
    required this.lean,
    required this.risen,
    required this.other,
    required this.recentStart,
    required this.previousStart,
  });

  final SubstanceDayCounts lean;
  final WatchedSubstance risen;
  final SubstanceDayCounts other;
  final DateTime recentStart;
  final DateTime previousStart;

  /// 0–100, rounded. 10 days down to 3 is 70.
  int get leanDropPercent {
    if (lean.previous <= 0) return 0;
    final dropped = lean.previous - lean.recent;
    if (dropped <= 0) return 0;
    return ((dropped / lean.previous) * 100).round();
  }

  String get title => 'A quiet heads-up';

  /// Warm, non-judgmental copy that uses their own numbers.
  String get body {
    final percent = leanDropPercent;
    final leanLine = percent >= 100
        ? 'No lean days in the last two weeks, nice work.'
        : 'Lean is down $percent%, nice work.';
    return '$leanLine ${risen.label} went from ${_weekPhrase(other.previous)} '
        'to ${_weekPhrase(other.recent)}, worth keeping an eye on.';
  }

  String get footer =>
      'If you want, you can talk this over with your SOS contact '
      'or a doctor. No pressure.';
}

/// Neutral notification copy. Never names a substance, recovery, or a person.
const swapWatchNotificationTitle = 'A quiet heads-up';
const swapWatchNotificationBody =
    'Something in your last two weeks is worth a look.';

/// Unique calendar days (local) of use for each [WatchedSubstance] in
/// [events], split into the last 14 days and the 14 days before that.
///
/// Times come from each event's `timestamp` (`occurredAt`). Benzo-only
/// events count as benzo days only — they never add a lean day and this
/// function never touches the lean timer.
Map<WatchedSubstance, SubstanceDayCounts> substanceDayCounts({
  required Iterable<RecoveryEvent> events,
  required DateTime now,
}) {
  final today = _dayOnly(now);
  final recentStart = today.subtract(
    const Duration(days: swapWatchWindowDays - 1),
  );
  final previousStart = today.subtract(
    const Duration(days: swapWatchWindowDays * 2 - 1),
  );
  final previousEnd = recentStart.subtract(const Duration(days: 1));

  final previous = {for (final s in WatchedSubstance.values) s: <String>{}};
  final recent = {for (final s in WatchedSubstance.values) s: <String>{}};

  for (final event in events) {
    if (event.type != RecoveryEventType.relapse) continue;
    if (event.timestamp.isAfter(now)) continue;
    final day = _dayOnly(event.timestamp);
    if (day.isBefore(previousStart) || day.isAfter(today)) continue;
    final key = _dateKey(day);
    final into = !day.isBefore(recentStart) ? recent : previous;
    if (day.isAfter(previousEnd) && day.isBefore(recentStart)) continue;
    for (final substance in substancesOn(event)) {
      into[substance]!.add(key);
    }
  }

  return {
    for (final s in WatchedSubstance.values)
      s: SubstanceDayCounts(
        previous: previous[s]!.length,
        recent: recent[s]!.length,
      ),
  };
}

/// When lean days dropped meaningfully and another substance's days rose
/// meaningfully, the insight to show. Otherwise null.
SwapWatchInsight? detectSwapWatch({
  required Iterable<RecoveryEvent> events,
  required DateTime now,
}) {
  final today = _dayOnly(now);
  final recentStart = today.subtract(
    const Duration(days: swapWatchWindowDays - 1),
  );
  final previousStart = today.subtract(
    const Duration(days: swapWatchWindowDays * 2 - 1),
  );
  final counts = substanceDayCounts(events: events, now: now);
  final lean = counts[WatchedSubstance.lean]!;
  if (!_leanDropped(lean)) return null;

  SwapWatchInsight? best;
  for (final substance in WatchedSubstance.values) {
    if (substance == WatchedSubstance.lean) continue;
    final other = counts[substance]!;
    if (!_otherRose(other)) continue;
    final candidate = SwapWatchInsight(
      lean: lean,
      risen: substance,
      other: other,
      recentStart: recentStart,
      previousStart: previousStart,
    );
    if (best == null ||
        other.delta > best.other.delta ||
        (other.delta == best.other.delta && other.recent > best.other.recent)) {
      best = candidate;
    }
  }
  return best;
}

/// Whether the card should be visible, given the toggle and the once-a-week
/// dismiss cooldown. A card that has not been dismissed stays up.
bool swapWatchIsVisible({
  required SwapWatchInsight? insight,
  required bool enabled,
  DateTime? dismissedAt,
  required DateTime now,
}) {
  if (!enabled || insight == null) return false;
  if (dismissedAt == null) return true;
  return !now.difference(dismissedAt).isNegative &&
      now.difference(dismissedAt) >= swapWatchCooldown;
}

/// Whether a new privacy-safe notification may be posted.
bool shouldNotifySwapWatch({
  required bool visible,
  DateTime? notifiedAt,
  required DateTime now,
  required bool quietHoursBlocked,
}) {
  if (!visible || quietHoursBlocked) return false;
  if (notifiedAt == null) return true;
  return now.difference(notifiedAt) >= swapWatchCooldown;
}

/// The substances a single relapse event counts toward. A lean+alcohol day
/// counts for both. A typeless (one-tap) log counts as lean, matching the
/// clean timer. Benzo-only never counts as lean.
Set<WatchedSubstance> substancesOn(RecoveryEvent event) {
  if (event.type != RecoveryEventType.relapse) return const {};
  final raw = RelapseTypeLabel.fromName(event.metadata['relapseType']);
  final text =
      '${event.metadata['note'] ?? ''} ${event.metadata['quantity'] ?? ''}';
  final type = raw == RelapseType.other && mentionsLeanBrand(text)
      ? RelapseType.fullLean
      : raw;
  final found = <WatchedSubstance>{};

  if (type == null ||
      type == RelapseType.fullLean ||
      type == RelapseType.partial ||
      type == RelapseType.leanPlusAlcohol) {
    found.add(WatchedSubstance.lean);
  }
  if (type == RelapseType.alcohol ||
      type == RelapseType.leanPlusAlcohol ||
      mentionsAlcohol(text)) {
    found.add(WatchedSubstance.alcohol);
  }
  if (type == RelapseType.benzo || mentionsBenzo(text)) {
    found.add(WatchedSubstance.benzo);
  }
  if (mentionsWeed(text)) {
    found.add(WatchedSubstance.weed);
  }
  if (type == RelapseType.other &&
      !found.contains(WatchedSubstance.lean) &&
      !found.contains(WatchedSubstance.weed) &&
      !found.contains(WatchedSubstance.alcohol) &&
      !found.contains(WatchedSubstance.benzo)) {
    found.add(WatchedSubstance.other);
  }
  return found;
}

bool mentionsWeed(String? text) => _mentioned(text, _weedWords);

bool mentionsAlcohol(String? text) => _mentioned(text, _alcoholWords);

bool mentionsBenzo(String? text) => _mentioned(text, _benzoWords);

bool _leanDropped(SubstanceDayCounts lean) {
  if (lean.previous < swapWatchMinPreviousLeanDays) return false;
  final drop = lean.previous - lean.recent;
  if (drop < 1) return false;
  return drop >= swapWatchMinLeanDropDays ||
      drop / lean.previous >= swapWatchMinLeanDropRatio;
}

bool _otherRose(SubstanceDayCounts other) =>
    other.delta >= swapWatchMinOtherRiseDays &&
    other.recent >= swapWatchMinOtherRiseDays;

String _weekPhrase(int daysInTwoWeeks) {
  final per = daysInTwoWeeks / 2;
  final label = per == per.roundToDouble()
      ? '${per.toInt()}'
      : per.toStringAsFixed(1);
  return label == '1' ? '1 day a week' : '$label days a week';
}

DateTime _dayOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _dateKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

final _weedWords = RegExp(
  r'\b(weed|ganja|cannabis|marijuana|charas|hashish|\bhash\b|thc|\bpot\b|joint|bhang)\b',
  caseSensitive: false,
);

final _alcoholWords = RegExp(
  r'\b(alcohol|beers?|wines?|vodka|whisky|whiskey|rum|gin|brandy|tequila)\b',
  caseSensitive: false,
);

final _benzoWords = RegExp(
  r'\b(benzo|benzos|alprazolam|xanax|valium|diazepam|clonazepam|klonopin|lorazepam|ativan|etizolam|nitrazepam)\b',
  caseSensitive: false,
);

/// Same negation idea as [mentionsLeanBrand]: "no beer" does not count.
bool _mentioned(String? text, RegExp words) {
  if (text == null || text.trim().isEmpty) return false;
  for (final m in words.allMatches(text)) {
    final clause = text
        .substring(0, m.start)
        .split(RegExp(r'[,.;!?]|\b(but|though|then)\b', caseSensitive: false))
        .last;
    if (!_negatedBefore.hasMatch(clause)) return true;
  }
  return false;
}

final _negatedBefore = RegExp(
  r"\b(no|not|never|without|instead of|skipped|avoided|didn'?t (have|take|buy|drink|use|smoke)|did not (have|take|buy|drink|use|smoke))\b(\s+\S+){0,2}\s*$",
  caseSensitive: false,
);
