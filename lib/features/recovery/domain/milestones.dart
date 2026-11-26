import 'event_derived_state.dart';
import 'recovery_event.dart';

/// A clean-streak milestone. Days are counted from the last dose, exactly
/// like the dashboard counter.
class RecoveryMilestone {
  const RecoveryMilestone(this.days, this.label);

  final int days;
  final String label;
}

const recoveryMilestones = <RecoveryMilestone>[
  RecoveryMilestone(3, 'BREAK THE LOOP'),
  RecoveryMilestone(7, 'FIRST WEEK'),
  RecoveryMilestone(14, 'HABIT PRESSURE DROPS'),
  RecoveryMilestone(30, 'NEW BASELINE'),
  RecoveryMilestone(60, 'SYSTEM REBUILT'),
  RecoveryMilestone(90, 'LONG GAME'),
  RecoveryMilestone(180, 'HALF A YEAR'),
  RecoveryMilestone(365, 'ONE YEAR CLEAN'),
];

RecoveryMilestone? milestoneFor(int days) {
  for (final milestone in recoveryMilestones) {
    if (milestone.days == days) return milestone;
  }
  return null;
}

/// Milestones reached in the current streak that have no milestone event
/// yet, smallest first. A relapse moves [lastDose], so every streak earns its
/// milestones again; events from earlier streaks never count, and neither do
/// milestones marked corrected by [reconcileMilestones].
List<RecoveryMilestone> dueMilestones({
  required Iterable<RecoveryEvent> events,
  required DateTime lastDose,
  required DateTime now,
}) {
  final recorded = <int>{
    for (final event in events)
      if (milestoneCounts(event) &&
          !event.timestamp.isBefore(lastDose) &&
          event.metadata['days'] is int)
        event.metadata['days'] as int,
  };
  return [
    for (final milestone in recoveryMilestones)
      if (!lastDose.add(Duration(days: milestone.days)).isAfter(now) &&
          !recorded.contains(milestone.days))
        milestone,
  ];
}

/// P0-5: a milestone whose reach time is before the moment the latest reset
/// was *recorded* was only "reached" on paper because the relapse was
/// backfilled later. It is logged silently and never celebrated.
bool milestoneIsBackfilled({
  required RecoveryMilestone milestone,
  required DateTime lastDose,
  required DateTime? resetRecordedAt,
}) {
  if (resetRecordedAt == null) return false;
  return lastDose.add(Duration(days: milestone.days)).isBefore(resetRecordedAt);
}

/// Metadata keys written by [reconcileMilestones] on an auto milestone that
/// a later-logged (backdated) relapse showed was never really reached.
const milestoneCorrectedKey = 'corrected';
const milestoneCorrectedReasonKey = 'correctedReason';
const milestoneCorrectedByKey = 'correctedBy';

/// Why a milestone was marked corrected.
const milestoneCorrectedRelapse = 'relapseBeforeMilestone';
const milestoneCorrectedDuplicate = 'duplicateInStreak';

/// Metadata key holding the `streakLost` a relapse was saved with, kept when
/// [reconcileMilestones] recomputes it from occurred times.
const streakLostRecordedKey = 'streakLostRecorded';

/// True for a milestone event that still counts: not marked corrected.
bool milestoneCounts(RecoveryEvent event) =>
    event.type == RecoveryEventType.milestone &&
    event.metadata[milestoneCorrectedKey] != true;

/// Whether this event starts a new lean/codeine streak, by occurred time.
/// Same set [computeLastDose] reads: lean/codeine relapses (benzo-only never
/// counts) and every recovery-start baseline.
bool _startsStreak(RecoveryEvent event) => resetsLeanCleanTimer(event);

/// Makes milestones and relapse `streakLost` agree with *occurred* time,
/// whatever order things were logged, edited or imported in.
///
/// * An auto milestone stamped at T for N days is only real if no
///   lean/codeine relapse happened in the N days before T. One that a
///   backdated relapse falls inside is marked `corrected` (never deleted),
///   stops counting toward best streak, and no longer blocks the same
///   milestone from being earned again in the new streak.
/// * If that relapse is later deleted (or re-typed as benzo-only) the
///   milestone counts again; a second copy earned meanwhile in the same
///   streak is marked corrected as a duplicate instead.
/// * A lean/codeine relapse's `streakLost` is recomputed from the reset
///   before it by occurred time; the saved value is kept in
///   [streakLostRecordedKey]. Relapses with no earlier reset keep theirs.
///
/// Pure and idempotent: returns [events] itself when nothing changes.
List<RecoveryEvent> reconcileMilestones(List<RecoveryEvent> events) {
  final resets = events.where(_startsStreak).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final relapseResets = resets
      .where((e) => e.type == RecoveryEventType.relapse)
      .toList();

  RecoveryEvent? latestResetAtOrBefore(DateTime at, {String? excludingId}) {
    RecoveryEvent? found;
    for (final reset in resets) {
      if (reset.timestamp.isAfter(at)) break;
      if (reset.id == excludingId) continue;
      found = reset;
    }
    return found;
  }

  var changed = false;
  final result = List<RecoveryEvent>.of(events);

  // Milestones, oldest first so the earliest valid copy in a streak wins.
  final milestoneIndexes = [
    for (var i = 0; i < result.length; i++)
      if (result[i].type == RecoveryEventType.milestone &&
          result[i].metadata['source'] == 'auto' &&
          result[i].metadata['days'] is int)
        i,
  ]..sort((a, b) => result[a].timestamp.compareTo(result[b].timestamp));
  final keptInStreak = <String>{};
  for (final index in milestoneIndexes) {
    final event = result[index];
    final days = event.metadata['days'] as int;
    final reachedAt = event.timestamp;
    final streakStartedBy = reachedAt.subtract(Duration(days: days));
    final breaker = relapseResets
        .where(
          (r) =>
              r.timestamp.isAfter(streakStartedBy) &&
              r.timestamp.isBefore(reachedAt),
        )
        .firstOrNull;
    String? reason;
    String? by;
    if (breaker != null) {
      reason = milestoneCorrectedRelapse;
      by = breaker.id;
    } else {
      final start = latestResetAtOrBefore(streakStartedBy);
      final key = '${start?.id ?? '-'}/$days';
      if (!keptInStreak.add(key)) reason = milestoneCorrectedDuplicate;
    }
    final metadata = Map<String, dynamic>.from(event.metadata);
    if (reason == null) {
      metadata
        ..remove(milestoneCorrectedKey)
        ..remove(milestoneCorrectedReasonKey)
        ..remove(milestoneCorrectedByKey);
    } else {
      metadata[milestoneCorrectedKey] = true;
      metadata[milestoneCorrectedReasonKey] = reason;
      if (by == null) {
        metadata.remove(milestoneCorrectedByKey);
      } else {
        metadata[milestoneCorrectedByKey] = by;
      }
    }
    if (!_sameMetadata(metadata, event.metadata)) {
      result[index] = event.copyWith(metadata: metadata);
      changed = true;
    }
  }

  // streakLost on lean/codeine relapses, from occurred time.
  for (var i = 0; i < result.length; i++) {
    final event = result[i];
    if (event.type != RecoveryEventType.relapse ||
        !resetsLeanCleanTimer(event)) {
      continue;
    }
    final previous = latestResetAtOrBefore(
      event.timestamp,
      excludingId: event.id,
    );
    if (previous == null) continue;
    final derived = event.timestamp.difference(previous.timestamp).inDays;
    final stored = event.metadata['streakLost'];
    if (stored == derived) continue;
    final metadata = Map<String, dynamic>.from(event.metadata);
    if (!metadata.containsKey(streakLostRecordedKey) && stored is num) {
      metadata[streakLostRecordedKey] = stored;
    }
    metadata['streakLost'] = derived;
    result[i] = event.copyWith(metadata: metadata);
    changed = true;
  }

  return changed ? result : events;
}

bool _sameMetadata(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
