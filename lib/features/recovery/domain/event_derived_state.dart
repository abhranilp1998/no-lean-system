import '../../../core/utils/formatters.dart';
import 'recovery_event.dart';

/// Finds the most recent counter-reset timestamp. A recovery-start event is a
/// neutral baseline and a relapse is a subsequent reset.
DateTime computeLastDose(List<RecoveryEvent> events) {
  final relapses = events
      .where((event) => event.type == RecoveryEventType.relapse)
      .toList();
  relapses.addAll(
    events.where(
      (event) =>
          event.type == RecoveryEventType.recoveryStart &&
          event.metadata['source'] == 'legacyLastDose',
    ),
  );
  if (relapses.isNotEmpty) {
    relapses.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return relapses.first.timestamp;
  }

  final baselines = events
      .where((event) => event.type == RecoveryEventType.recoveryStart)
      .toList();
  if (baselines.isNotEmpty) {
    baselines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return baselines.first.timestamp;
  }
  if (events.isEmpty) return DateTime.now();
  return events
      .map((event) => event.timestamp)
      .reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Builds the clean days map.
/// A day is clean (`true`) if there's a pledge/cleanCheckIn event for that date key AND no relapse event for that date.
/// A day is unclean (`false`) if there's a relapse event for that date.
Map<String, bool> computeCleanDaysMap(List<RecoveryEvent> events) {
  final map = <String, bool>{};

  for (final event in events) {
    final key = event.type == RecoveryEventType.daySummary
        ? event.metadata['date'] as String
        : dateKey(event.timestamp.toLocal());
    if (event.type == RecoveryEventType.daySummary) {
      if (map[key] != false) map[key] = event.metadata['clean'] as bool;
    }
    if (event.type == RecoveryEventType.relapse) {
      map[key] = false;
    } else if (event.type == RecoveryEventType.pledge ||
        event.type == RecoveryEventType.cleanCheckIn) {
      if (map[key] != false) {
        map[key] = true;
      }
    }
  }

  return map;
}

/// Counts consecutive clean days backwards from today.
/// A day counts as clean if it has a pledge/cleanCheckIn and no relapse.
int computeCurrentStreak(List<RecoveryEvent> events) {
  final cleanMap = computeCleanDaysMap(events);
  int streak = 0;
  DateTime current = DateTime.now();

  while (true) {
    final key = dateKey(current);
    if (cleanMap[key] == true) {
      streak++;
      current = current.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }

  return streak;
}

/// Finds the longest consecutive run of clean days across all time.
int computeLongestStreak(List<RecoveryEvent> events) {
  final cleanMap = computeCleanDaysMap(events);
  final historicalBest = events
      .where(
        (event) =>
            event.type == RecoveryEventType.milestone ||
            event.type == RecoveryEventType.relapse,
      )
      .map(
        (event) => event.type == RecoveryEventType.milestone
            ? event.metadata['days']
            : event.metadata['streakLost'],
      )
      .whereType<num>()
      .fold<int>(0, (best, days) => days.round() > best ? days.round() : best);
  if (cleanMap.isEmpty || events.isEmpty) return historicalBest;

  final days = cleanMap.keys.toList()..sort();
  int longest = 0;
  int currentStreak = 0;
  DateTime? previous;
  for (final key in days) {
    final day = DateTime.parse('${key}T00:00:00Z');
    if (cleanMap[key] == true) {
      currentStreak = previous != null && day.difference(previous).inDays == 1
          ? currentStreak + 1
          : 1;
      if (currentStreak > longest) longest = currentStreak;
    } else {
      currentStreak = 0;
    }
    previous = day;
  }

  return longest > historicalBest ? longest : historicalBest;
}

/// Counts completed SOS sessions that were NOT followed by a relapse within [windowMinutes].
/// Returns a record with `held` (sessions that didn't lead to relapse) and `total` (all completed SOS sessions).
({int held, int total}) computePostSosHoldRate(
  List<RecoveryEvent> events,
  int windowMinutes,
) {
  final sosCompleteEvents = events
      .where((e) => e.type == RecoveryEventType.sosComplete)
      .toList();
  final relapseEvents = events
      .where((e) => e.type == RecoveryEventType.relapse)
      .toList();

  int held = 0;
  int total = sosCompleteEvents.length;

  for (final sos in sosCompleteEvents) {
    final limit = sos.timestamp.add(Duration(minutes: windowMinutes));
    final hasRelapse = relapseEvents.any(
      (r) => r.timestamp.isAfter(sos.timestamp) && r.timestamp.isBefore(limit),
    );

    if (!hasRelapse) {
      held++;
    }
  }

  return (held: held, total: total);
}

/// Returns the hours of day (0-23) sorted by frequency of craving and relapse events.
/// Useful for scheduling adaptive reminders.
List<int> computeHighRiskHours(List<RecoveryEvent> events) {
  final hourCounts = <int, int>{};

  for (final event in events) {
    if (event.type == RecoveryEventType.craving ||
        event.type == RecoveryEventType.relapse) {
      final hour = event.timestamp.hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
    }
  }

  final sortedEntries = hourCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return sortedEntries.map((e) => e.key).toList();
}
