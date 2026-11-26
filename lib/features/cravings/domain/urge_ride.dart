import '../../recovery/domain/recovery_event.dart';
import '../../recovery/domain/slip_tone.dart';

/// Length of the ride-it-out timer. The existing urge-surf screen already
/// accepted a duration; ten minutes is the default for this flow.
const urgeRideDuration = Duration(minutes: 10);

/// An activity needs at least this many logged rides before it is ranked.
const whatWorkedMinSample = 3;

/// One phase of the optional haptic breathing pace (4 seconds in, 4 out).
const breathPhaseSeconds = 4;

enum BreathPhase { inhale, exhale }

BreathPhase breathPhaseAt(Duration elapsed) {
  final step = elapsed.inSeconds % (breathPhaseSeconds * 2);
  return step < breathPhaseSeconds ? BreathPhase.inhale : BreathPhase.exhale;
}

String breathPhaseLabel(BreathPhase phase) => switch (phase) {
  BreathPhase.inhale => 'Breathe in',
  BreathPhase.exhale => 'Breathe out',
};

/// "Did it pass?" at the end of a ride.
enum UrgeRideOutcome { yes, aBit, no }

extension UrgeRideOutcomeInfo on UrgeRideOutcome {
  String get label => switch (this) {
    UrgeRideOutcome.yes => 'Yes',
    UrgeRideOutcome.aBit => 'A bit',
    UrgeRideOutcome.no => 'Not yet',
  };

  String get cravingOutcome => switch (this) {
    UrgeRideOutcome.yes => 'gone',
    UrgeRideOutcome.aBit => 'eased',
    UrgeRideOutcome.no => 'same',
  };

  /// Intensity written on the linked craving-check, 0–10.
  int intensityAfter(int before) => switch (this) {
    UrgeRideOutcome.yes => 0,
    UrgeRideOutcome.aBit =>
      before <= 1 ? 1 : (before / 2).round().clamp(1, before - 1),
    UrgeRideOutcome.no => before.clamp(1, 10),
  };

  static UrgeRideOutcome fromCravingOutcome(String? outcome) =>
      switch (outcome) {
        'gone' => UrgeRideOutcome.yes,
        'eased' => UrgeRideOutcome.aBit,
        _ => UrgeRideOutcome.no,
      };

  static UrgeRideOutcome? fromName(Object? name) {
    if (name is! String) return null;
    return UrgeRideOutcome.values.where((o) => o.name == name).firstOrNull;
  }
}

enum UrgeRideActivity { walk, call, music, food, shower, breathing, other }

extension UrgeRideActivityInfo on UrgeRideActivity {
  String get label => switch (this) {
    UrgeRideActivity.walk => 'Walk',
    UrgeRideActivity.call => 'Call',
    UrgeRideActivity.music => 'Music',
    UrgeRideActivity.food => 'Food',
    UrgeRideActivity.shower => 'Shower',
    UrgeRideActivity.breathing => 'Breathing',
    UrgeRideActivity.other => 'Other',
  };

  static UrgeRideActivity fromName(Object? name) =>
      UrgeRideActivity.values.where((a) => a.name == name).firstOrNull ??
      UrgeRideActivity.other;
}

/// One finished 10-minute (or shorter) ride, derived from existing event
/// types plus optional metadata. Older saves without those keys are simply
/// not rides.
class UrgeRide {
  const UrgeRide({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.outcome,
    required this.activity,
    this.hapticPacing = false,
    this.intensityBefore = 5,
    this.plannedMinutes = 10,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final UrgeRideOutcome outcome;
  final UrgeRideActivity activity;
  final bool hapticPacing;
  final int intensityBefore;
  final int plannedMinutes;

  bool get passed => outcome == UrgeRideOutcome.yes;

  static UrgeRide? fromCheck(RecoveryEvent check, {RecoveryEvent? craving}) {
    if (check.type != RecoveryEventType.cravingCheck) return null;
    if (check.metadata['urgeRide'] != true) return null;
    final started = craving?.timestamp ?? check.timestamp;
    final before = (craving?.metadata['intensity'] as num?)?.round() ?? 5;
    final outcome =
        UrgeRideOutcomeInfo.fromName(check.metadata['didPass']) ??
        UrgeRideOutcomeInfo.fromCravingOutcome(
          check.metadata['outcome'] as String?,
        );
    final planned = (check.metadata['plannedMinutes'] as num?)?.round() ?? 10;
    return UrgeRide(
      id: check.id,
      startedAt: started,
      endedAt: check.timestamp,
      outcome: outcome,
      activity: UrgeRideActivityInfo.fromName(check.metadata['activity']),
      hapticPacing: check.metadata['hapticPacing'] == true,
      intensityBefore: before.clamp(1, 10),
      plannedMinutes: planned,
    );
  }

  static List<UrgeRide> fromEvents(List<RecoveryEvent> events) {
    final cravings = {
      for (final event in events)
        if (event.type == RecoveryEventType.craving) event.id: event,
    };
    final rides = <UrgeRide>[];
    for (final event in events) {
      final id = event.metadata['cravingId'];
      final ride = fromCheck(
        event,
        craving: id is String ? cravings[id] : null,
      );
      if (ride != null) rides.add(ride);
    }
    rides.sort((a, b) => a.endedAt.compareTo(b.endedAt));
    return rides;
  }

  /// Metadata for the starting craving event. Extra keys are optional.
  Map<String, dynamic> cravingMetadata() => {
    'intensity': intensityBefore.clamp(1, 10),
    'trigger': 'Ride it out',
    'note': 'Ten-minute ride',
    'urgeRide': true,
  };

  /// Metadata for the closing craving-check event. Extra keys are optional
  /// so an older app still reads this as a normal recheck.
  Map<String, dynamic> checkMetadata(String cravingId) => {
    'cravingId': cravingId,
    'intensity': outcome.intensityAfter(intensityBefore),
    'outcome': outcome.cravingOutcome,
    'originalIntensity': intensityBefore,
    'urgeRide': true,
    'didPass': outcome.name,
    'activity': activity.name,
    'hapticPacing': hapticPacing,
    'plannedMinutes': plannedMinutes,
  };
}

class ActivityRank {
  const ActivityRank({
    required this.activity,
    required this.total,
    required this.passed,
    required this.eased,
  });

  final UrgeRideActivity activity;
  final int total;
  final int passed;
  final int eased;

  /// Yes counts fully, "a bit" counts half. Needs [whatWorkedMinSample]
  /// before it is used for ranking.
  double get passRate => total == 0 ? 0 : (passed + eased * 0.5) / total;

  bool get hasEnough => total >= whatWorkedMinSample;

  String get scoreLabel {
    if (eased == 0) return '$passed of $total';
    if (passed == 0) return '$eased eased of $total';
    return '$passed passed, $eased eased';
  }
}

class WhatWorkedStats {
  WhatWorkedStats(this.rides);

  factory WhatWorkedStats.fromEvents(List<RecoveryEvent> events) =>
      WhatWorkedStats(UrgeRide.fromEvents(events));

  final List<UrgeRide> rides;

  int get total => rides.length;
  int get passed => rides.where((r) => r.outcome == UrgeRideOutcome.yes).length;
  int get eased => rides.where((r) => r.outcome == UrgeRideOutcome.aBit).length;

  double get successRate => total == 0 ? 0 : (passed + eased * 0.5) / total;

  List<ActivityRank> get ranks {
    final ranks = <ActivityRank>[
      for (final activity in UrgeRideActivity.values)
        if (rides.any((r) => r.activity == activity))
          ActivityRank(
            activity: activity,
            total: rides.where((r) => r.activity == activity).length,
            passed: rides
                .where(
                  (r) =>
                      r.activity == activity &&
                      r.outcome == UrgeRideOutcome.yes,
                )
                .length,
            eased: rides
                .where(
                  (r) =>
                      r.activity == activity &&
                      r.outcome == UrgeRideOutcome.aBit,
                )
                .length,
          ),
    ];
    ranks.sort((a, b) {
      final rate = b.passRate.compareTo(a.passRate);
      if (rate != 0) return rate;
      final n = b.total.compareTo(a.total);
      if (n != 0) return n;
      return a.activity.label.compareTo(b.activity.label);
    });
    return ranks;
  }

  List<ActivityRank> get ranked =>
      ranks.where((r) => r.hasEnough).toList(growable: false);

  List<ActivityRank> get waiting =>
      ranks.where((r) => !r.hasEnough).toList(growable: false);

  ActivityRank? get top => ranked.firstOrNull;

  String get homeHeadline {
    if (total == 0) return 'Ride one out and I will keep score with you.';
    if (passed == 0 && eased == 0) {
      return 'You stayed with $total ${total == 1 ? 'urge' : 'urges'}. That still counts.';
    }
    if (passed == total) {
      return total == 1
          ? 'You rode that one out.'
          : 'You have ridden all $total of these out.';
    }
    return 'You have ridden $passed of $total of these out.';
  }

  String get homeBody {
    final best = top;
    if (best != null) {
      return '${best.activity.label} has been the most reliable for you so far (${best.passed} of ${best.total}).';
    }
    if (total == 0) {
      return 'Ten minutes, a walk, a song, a shower — whatever you try, I will remember what helps.';
    }
    return 'A few more rides and I can rank what works for you.';
  }

  /// True when every user-facing line stays warm and helpline-free.
  bool get copyIsWarm => isWarmCopy(homeHeadline) && isWarmCopy(homeBody);
}

String? urgeRideHistoryLabel(RecoveryEvent event) {
  final ride = UrgeRide.fromCheck(event);
  if (ride == null) return null;
  final passed = switch (ride.outcome) {
    UrgeRideOutcome.yes => 'IT PASSED',
    UrgeRideOutcome.aBit => 'IT EASED',
    UrgeRideOutcome.no => 'STILL THERE',
  };
  return 'RIDE IT OUT // ${ride.activity.label.toUpperCase()} // $passed';
}
