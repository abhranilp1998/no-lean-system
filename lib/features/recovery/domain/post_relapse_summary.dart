import 'recovery_event.dart';
import 'relapse_log_entry.dart';

/// Facts for the screen shown while the app re-locks after a relapse log.
///
/// Everything here is derived from the existing event log, so no state or
/// backup format changes. Old data that lacks a field (no `streakLost`, no
/// `relapseType`, no `recordedAt`) simply falls back to calmer copy.
class PostRelapseSummary {
  const PostRelapseSummary({
    required this.previousDays,
    required this.bestDays,
    required this.timerKept,
    required this.mixingRisk,
    required this.lowerTolerance,
    required this.seed,
  });

  /// Clean days built before the slip that was just logged. When the slip did
  /// not reset the lean timer (see [timerKept]) this is the live streak.
  final int previousDays;

  /// Longest clean run ever, never lower than [previousDays].
  final int bestDays;

  /// True when the latest log was benzo-only and the lean timer was kept.
  final bool timerKept;

  /// A sedative or alcohol was logged within the last 24 hours.
  final bool mixingRisk;

  /// The streak that just ended lasted 3 days or more, so tolerance is lower.
  final bool lowerTolerance;

  /// Stable per-slip number used to rotate the encouraging line.
  final int seed;

  /// Whether there is a real streak to show.
  bool get hasStreak => previousDays > 0;
}

const lowerToleranceMinDays = 3;

const _mixingTypes = {
  RelapseType.benzo,
  RelapseType.alcohol,
  RelapseType.leanPlusAlcohol,
};

bool _resets(RecoveryEvent e) =>
    RelapseTypeLabel.fromName(e.metadata['relapseType']) != RelapseType.benzo;

DateTime _loggedAt(RecoveryEvent e) {
  final raw = e.metadata['recordedAt'];
  final parsed = raw is String ? DateTime.tryParse(raw) : null;
  return parsed ?? e.timestamp;
}

/// Builds the summary from [events]. [liveStreakDays] and [longestStreakDays]
/// come from the controller, so the numbers match the dashboard exactly.
PostRelapseSummary buildPostRelapseSummary({
  required List<RecoveryEvent> events,
  required DateTime now,
  required int liveStreakDays,
  required int longestStreakDays,
}) {
  final relapses =
      events.where((e) => e.type == RecoveryEventType.relapse).toList()..sort((
        a,
        b,
      ) {
        final byTime = _loggedAt(a).compareTo(_loggedAt(b));
        if (byTime != 0) return byTime;
        // Same instant (one mixed save): put the timer-resetting entry last so
        // a lean + benzo save counts as a reset, not as "benzo only".
        return (_resets(a) ? 1 : 0).compareTo(_resets(b) ? 1 : 0);
      });

  RecoveryEvent? latest = relapses.isEmpty ? null : relapses.last;
  RecoveryEvent? latestReset;
  for (final e in relapses.reversed) {
    final type = RelapseTypeLabel.fromName(e.metadata['relapseType']);
    if (type != RelapseType.benzo) {
      latestReset = e;
      break;
    }
  }

  final latestType = latest == null
      ? null
      : RelapseTypeLabel.fromName(latest.metadata['relapseType']);
  // A benzo-only log keeps the lean timer. If the live streak is already 0
  // (a lean slip came first), there is no streak to call intact.
  final timerKept = latestType == RelapseType.benzo && liveStreakDays > 0;

  var previous = 0;
  if (timerKept) {
    previous = liveStreakDays;
  } else if (latestReset != null) {
    final lost = latestReset.metadata['streakLost'];
    if (lost is num) previous = lost.round();
  }
  if (previous < 0) previous = 0;

  final cutoff = now.subtract(const Duration(hours: 24));
  final mixing = relapses.any((e) {
    final type = RelapseTypeLabel.fromName(e.metadata['relapseType']);
    if (type == null || !_mixingTypes.contains(type)) return false;
    final at = _loggedAt(e);
    final occurred = e.timestamp;
    return (at.isAfter(cutoff) && !at.isAfter(now)) ||
        (occurred.isAfter(cutoff) && !occurred.isAfter(now));
  });

  return PostRelapseSummary(
    previousDays: previous,
    bestDays: longestStreakDays > previous ? longestStreakDays : previous,
    timerKept: timerKept,
    mixingRisk: mixing,
    lowerTolerance: !timerKept && previous >= lowerToleranceMinDays,
    seed: relapses.length + now.day,
  );
}

/// Time-of-day greeting. Warm and short, never clinical.
String postRelapseGreeting(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Still up? I am here.';
  if (h < 12) return 'Good morning.';
  if (h < 17) return 'Good afternoon.';
  if (h < 22) return 'Good evening.';
  return 'It is late. I am here.';
}

/// Rotating encouragement. Plain, human, no judgement. Deterministic by seed.
const postRelapseEncouragements = <String>[
  'One slip is a moment, not the whole story.',
  'You came back to the app instead of hiding. That matters.',
  'Progress is not a straight line. You still know the way.',
  'Be as kind to yourself as you would be to a friend.',
  'The days you built happened. Nothing can undo them.',
  'Tomorrow is a clean page, and you are allowed to start it.',
  'Telling the truth about a bad night is a skill. You have it.',
  'You do not have to fix everything tonight. Just the next hour.',
];

String postRelapseEncouragement(int seed) =>
    postRelapseEncouragements[seed.abs() % postRelapseEncouragements.length];

/// One step of the gentle next-24-hours plan.
class NextStep {
  const NextStep({required this.when, required this.title, required this.body});
  final String when;
  final String title;
  final String body;
}

/// Three concrete steps. Private wording: no substance names.
/// [contactName] is the user's own trusted contact, when one is saved.
List<NextStep> nextTwentyFourHours({
  required DateTime now,
  required bool mixingRisk,
  String? contactName,
}) {
  final late = now.hour >= 20 || now.hour < 5;
  final who = contactName == null || contactName.trim().isEmpty
      ? 'someone you trust'
      : contactName.trim();
  return [
    const NextStep(
      when: 'NOW',
      title: 'Water, then something to eat',
      body:
          'A full glass of water and a small meal, even toast. '
          'Your body is doing extra work right now.',
    ),
    NextStep(
      when: late ? 'TONIGHT' : 'TODAY',
      title: 'Do not be alone with it',
      body: mixingRisk
          ? 'Stay near $who or another person and do not use anything more. '
                'Let them know tonight is a risky one.'
          : 'Keep $who within reach, or be around people. '
                'If you do slip again, do not do it alone.',
    ),
    NextStep(
      when: 'TOMORROW',
      title: 'Sleep, then check in',
      body:
          'Sleep as early as you can. Tomorrow morning, open the app, '
          'tick today, and tell $who how it went if you want to.',
    ),
  ];
}
