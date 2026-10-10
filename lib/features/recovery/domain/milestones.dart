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
/// milestones again; events from earlier streaks never count.
List<RecoveryMilestone> dueMilestones({
  required Iterable<RecoveryEvent> events,
  required DateTime lastDose,
  required DateTime now,
}) {
  final recorded = <int>{
    for (final event in events)
      if (event.type == RecoveryEventType.milestone &&
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
