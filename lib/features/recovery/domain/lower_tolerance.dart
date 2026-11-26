import 'event_derived_state.dart';
import 'recovery_event.dart';
import 'relapse_log_entry.dart';

/// A lower-tolerance card is shown when a qualifying slip is saved after a
/// clean gap of more than this many days, measured from [occurredAt].
const lowerToleranceAfterDays = 5;

/// Which card to show. Lean/codeine (including mixed saves) uses [lean];
/// benzo-only slips use the gentler [benzo] note and never move the lean
/// timer — this type is display-only.
enum ToleranceWarningKind { lean, benzo }

/// Facts for the full-screen lower-tolerance card shown after a save.
class ToleranceWarning {
  const ToleranceWarning({
    required this.kind,
    required this.cleanDays,
    required this.occurredAt,
    this.mixed = false,
  });

  final ToleranceWarningKind kind;
  final int cleanDays;
  final DateTime occurredAt;

  /// True when this save also combined lean/codeine with a benzo or alcohol.
  final bool mixed;

  bool get isBenzoOnly => kind == ToleranceWarningKind.benzo;

  String get title => kind == ToleranceWarningKind.benzo
      ? 'Benzos hit harder after a break'
      : 'Your body handles less now';

  /// Warm, non-judgmental copy that uses their own number of days.
  String get body {
    final days = _days(cleanDays);
    if (kind == ToleranceWarningKind.benzo) {
      return 'You had $days without benzos, so they hit harder now. '
          'A smaller amount than before can be enough. '
          'This does not change your lean clean time.';
    }
    if (mixed) {
      return 'You were clean $days, so your body handles less now. '
          'Your old amount hits much harder, and mixing with benzos or '
          'alcohol makes that even more dangerous.';
    }
    return 'You were clean $days, so your body handles less now. '
        'Your old amount hits much harder, especially with benzos or alcohol.';
  }

  String get footer =>
      'You do not have to be alone with this. Call your SOS contact, '
      'or a doctor or hospital, if you need someone.';
}

String _days(int n) => n == 1 ? '1 day' : '$n days';

bool containsLean(RelapseType? type) =>
    type == null ||
    type == RelapseType.fullLean ||
    type == RelapseType.partial ||
    type == RelapseType.leanPlusAlcohol;

/// The first qualifying lower-tolerance warning in [entries], or null.
///
/// [entries] are the slips about to be saved (one event, several events, or
/// a multi-day catch-up). The card is shown once, for the first qualifying
/// lean/codeine dose; if none qualify, for the first qualifying benzo-only
/// dose. Gaps are measured from each dose's [RelapseLogEntry.occurredAt]
/// against already-saved history plus earlier doses in this same save.
/// Benzo-only gaps never use a result that would move the lean timer.
ToleranceWarning? lowerToleranceWarning({
  required Iterable<RecoveryEvent> existingEvents,
  required Iterable<RelapseLogEntry> entries,
}) {
  final history = existingEvents.toList();
  final sorted = List<RelapseLogEntry>.of(entries)
    ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  if (sorted.isEmpty) return null;

  final mixed = isMixedTypes(sorted.map((e) => e.effectiveType));
  final extraLean = <DateTime>[];
  final extraBenzo = <DateTime>[];
  ToleranceWarning? firstLean;
  ToleranceWarning? firstBenzo;

  for (final entry in sorted) {
    final type = entry.effectiveType;
    final at = entry.occurredAt;
    if (containsLean(type)) {
      final prev = _latestAtOrBefore([
        ..._leanResetTimes(history),
        ...extraLean,
      ], at);
      if (firstLean == null && prev != null) {
        final days = at.difference(prev).inDays;
        if (days > lowerToleranceAfterDays) {
          firstLean = ToleranceWarning(
            kind: ToleranceWarningKind.lean,
            cleanDays: days,
            occurredAt: at,
            mixed: mixed,
          );
        }
      }
      extraLean.add(at);
    } else if (type == RelapseType.benzo) {
      final prev =
          _latestAtOrBefore([..._benzoTimes(history), ...extraBenzo], at) ??
          _latestAtOrBefore([..._leanResetTimes(history), ...extraLean], at);
      if (firstBenzo == null && prev != null) {
        final days = at.difference(prev).inDays;
        if (days > lowerToleranceAfterDays) {
          firstBenzo = ToleranceWarning(
            kind: ToleranceWarningKind.benzo,
            cleanDays: days,
            occurredAt: at,
          );
        }
      }
      extraBenzo.add(at);
    }
  }
  return firstLean ?? firstBenzo;
}

/// Lean + benzo or alcohol in one save (mirrors [isMixedSave] without
/// importing the mixing-safety module, so this file stays free of UI/prefs).
bool isMixedTypes(Iterable<RelapseType> types) {
  final t = types.toSet();
  if (t.contains(RelapseType.leanPlusAlcohol)) return true;
  final codeine =
      t.contains(RelapseType.fullLean) || t.contains(RelapseType.partial);
  return codeine &&
      (t.contains(RelapseType.alcohol) || t.contains(RelapseType.benzo));
}

List<DateTime> _leanResetTimes(Iterable<RecoveryEvent> events) => [
  for (final event in events)
    if (resetsLeanCleanTimer(event)) event.timestamp,
];

List<DateTime> _benzoTimes(Iterable<RecoveryEvent> events) => [
  for (final event in events)
    if (event.type == RecoveryEventType.relapse &&
        RelapseTypeLabel.fromName(event.metadata['relapseType']) ==
            RelapseType.benzo)
      event.timestamp,
];

DateTime? _latestAtOrBefore(Iterable<DateTime> times, DateTime at) {
  DateTime? best;
  for (final time in times) {
    if (time.isAfter(at)) continue;
    if (best == null || time.isAfter(best)) best = time;
  }
  return best;
}
