import '../../recovery/domain/craving_entry.dart';
import '../../recovery/domain/sos_session.dart';

class InsightBreakdown {
  const InsightBreakdown({
    required this.label,
    required this.count,
    required this.ratio,
    required this.averageIntensity,
  });

  final String label;
  final int count;
  final double ratio;
  final double averageIntensity;
}

class CravingSeriesPoint {
  const CravingSeriesPoint({required this.timestamp, required this.intensity});

  final DateTime timestamp;
  final int intensity;
}

class WeeklyRecoverySummary {
  const WeeklyRecoverySummary({
    required this.periodStart,
    required this.periodEnd,
    required this.cravingCount,
    required this.averageIntensity,
    required this.peakIntensity,
    required this.cleanDays,
    required this.sosStarted,
    required this.sosCompleted,
  });

  final DateTime periodStart;
  final DateTime periodEnd;
  final int cravingCount;
  final double averageIntensity;
  final int peakIntensity;
  final int cleanDays;
  final int sosStarted;
  final int sosCompleted;

  double get sosCompletionRate =>
      sosStarted == 0 ? 0 : sosCompleted / sosStarted;
}

class SosCompletionSummary {
  const SosCompletionSummary({
    required this.started,
    required this.completed,
    required this.averageDuration,
    required this.lastCompletedAt,
  });

  final int started;
  final int completed;
  final Duration? averageDuration;
  final DateTime? lastCompletedAt;

  double get completionRate => started == 0 ? 0 : completed / started;
}

enum PatternActionKind { logCraving, openSos, editRiskWindow, pledge }

class PatternActionInsight {
  const PatternActionInsight({
    required this.title,
    required this.body,
    required this.evidence,
    required this.actionLabel,
    required this.action,
  });

  final String title;
  final String body;
  final String evidence;
  final String actionLabel;
  final PatternActionKind action;
}

List<PatternActionInsight> patternActionInsights({
  required Iterable<CravingEntry> cravings,
  required Iterable<SosSession> sosSessions,
  required double dailySpend,
  required double moneySaved,
}) {
  final entries = cravings.toList();
  final sessions = sosSessions.toList();
  final results = <PatternActionInsight>[];

  final highIntensityByDay = <String, int>{};
  for (final entry in entries.where((entry) => _intensity(entry) >= 8)) {
    final key = _dateKey(entry.createdAt);
    highIntensityByDay[key] = (highIntensityByDay[key] ?? 0) + 1;
  }
  if (highIntensityByDay.isNotEmpty) {
    final strongest = highIntensityByDay.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    if (strongest.value >= 2) {
      results.add(
        PatternActionInsight(
          title: 'REPEAT SPIKE DETECTED',
          body:
              '${strongest.value} cravings hit 8/10 or higher on one day. Do not wait for the next spike: leave the buying route and run the full override.',
          evidence:
              '${strongest.value} HIGH-INTENSITY LOGS // ${strongest.key}',
          actionLabel: 'OPEN SOS NOW',
          action: PatternActionKind.openSos,
        ),
      );
    }
  }

  final triggers = triggerBreakdown(entries);
  if (triggers.isNotEmpty && triggers.first.count >= 2) {
    final dominant = triggers.first;
    results.add(
      PatternActionInsight(
        title: '${dominant.label.toUpperCase()} OWNS THE LOOP',
        body:
            '${(dominant.ratio * 100).round()}% of your ${entries.length} logged cravings point here. Before the next exposure: change location, remove the payment path, and open SOS before negotiating.',
        evidence:
            '${dominant.count} OF ${entries.length} LOGS // AVG ${dominant.averageIntensity.toStringAsFixed(1)}/10',
        actionLabel: 'PRACTICE SOS',
        action: PatternActionKind.openSos,
      ),
    );
  }

  final timeBands = timeOfDayBreakdown(entries);
  if (timeBands.isNotEmpty) {
    final dominant = timeBands.reduce((a, b) => a.count >= b.count ? a : b);
    if (dominant.count >= 2) {
      results.add(
        PatternActionInsight(
          title: '${dominant.label} IS THE EXPOSED BAND',
          body:
              'Start protection before this band, not inside it. Move the risk window earlier and keep the peak-hour lock armed.',
          evidence:
              '${dominant.count} OF ${entries.length} LOGS // ${(dominant.ratio * 100).round()}%',
          actionLabel: 'TUNE RISK WINDOW',
          action: PatternActionKind.editRiskWindow,
        ),
      );
    }
  }

  final sos = sosCompletionSummary(sessions);
  if (sos.started >= 2 && sos.completionRate < .6) {
    results.add(
      PatternActionInsight(
        title: 'THE OVERRIDE IS BEING CUT SHORT',
        body:
            'Only ${sos.completed} of ${sos.started} SOS runs reached the end. Rehearse the full minute while calm so the sequence is familiar under pressure.',
        evidence: '${(sos.completionRate * 100).round()}% COMPLETION',
        actionLabel: 'RUN A FULL SOS',
        action: PatternActionKind.openSos,
      ),
    );
  }

  if (dailySpend > 0 && moneySaved >= dailySpend) {
    results.add(
      PatternActionInsight(
        title: 'MOVE THE MONEY OUT OF RANGE',
        body:
            'Your clean time has retained ${moneySaved.toStringAsFixed(0)} in tracked spend. Move today\'s ${dailySpend.toStringAsFixed(0)} away from the usual buying path, then lock the pledge.',
        evidence:
            '${moneySaved.toStringAsFixed(0)} RETAINED // ${dailySpend.toStringAsFixed(0)} DAILY',
        actionLabel: 'LOCK TODAY',
        action: PatternActionKind.pledge,
      ),
    );
  }

  if (results.isEmpty) {
    results.add(
      const PatternActionInsight(
        title: 'BUILD THE SIGNAL BASELINE',
        body:
            'Log the hour, intensity, and real trigger when a craving hits. Three honest signals are more useful than a confident guess.',
        evidence: 'LESS THAN 3 REPEAT SIGNALS',
        actionLabel: 'LOG A CRAVING',
        action: PatternActionKind.logCraving,
      ),
    );
  }

  return List.unmodifiable(results.take(4));
}

List<InsightBreakdown> triggerBreakdown(Iterable<CravingEntry> entries) {
  final groups = <String, _BreakdownAccumulator>{};
  var total = 0;

  for (final entry in entries) {
    final trimmed = entry.trigger.trim();
    final label = trimmed.isEmpty ? 'Other' : trimmed;
    final key = label.toLowerCase();
    final accumulator = groups.putIfAbsent(
      key,
      () => _BreakdownAccumulator(label),
    );
    accumulator
      ..count += 1
      ..totalIntensity += _intensity(entry);
    total++;
  }

  if (total == 0) return const [];
  final result = groups.values
      .map(
        (group) => InsightBreakdown(
          label: group.label,
          count: group.count,
          ratio: group.count / total,
          averageIntensity: group.totalIntensity / group.count,
        ),
      )
      .toList();
  result.sort(_sortBreakdowns);
  return List.unmodifiable(result);
}

List<InsightBreakdown> timeOfDayBreakdown(Iterable<CravingEntry> entries) {
  final groups = <String, _BreakdownAccumulator>{
    'OVERNIGHT / 00-05': _BreakdownAccumulator('OVERNIGHT / 00-05'),
    'MORNING / 06-11': _BreakdownAccumulator('MORNING / 06-11'),
    'AFTERNOON / 12-16': _BreakdownAccumulator('AFTERNOON / 12-16'),
    'EVENING / 17-23': _BreakdownAccumulator('EVENING / 17-23'),
  };
  var total = 0;

  for (final entry in entries) {
    final hour = entry.createdAt.toLocal().hour;
    final key = switch (hour) {
      < 6 => 'OVERNIGHT / 00-05',
      < 12 => 'MORNING / 06-11',
      < 17 => 'AFTERNOON / 12-16',
      _ => 'EVENING / 17-23',
    };
    groups[key]!
      ..count += 1
      ..totalIntensity += _intensity(entry);
    total++;
  }

  if (total == 0) return const [];
  return List.unmodifiable(
    groups.values.map(
      (group) => InsightBreakdown(
        label: group.label,
        count: group.count,
        ratio: group.count / total,
        averageIntensity: group.count == 0
            ? 0
            : group.totalIntensity / group.count,
      ),
    ),
  );
}

List<CravingSeriesPoint> chronologicalCravingSeries(
  Iterable<CravingEntry> entries,
) {
  final points =
      entries
          .map(
            (entry) => CravingSeriesPoint(
              timestamp: entry.createdAt,
              intensity: _intensity(entry),
            ),
          )
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return List.unmodifiable(points);
}

WeeklyRecoverySummary weeklyRecoverySummary({
  required Iterable<CravingEntry> cravings,
  required Iterable<SosSession> sosSessions,
  required Map<String, bool> cleanDays,
  DateTime? now,
}) {
  final localNow = (now ?? DateTime.now()).toLocal();
  final periodEnd = DateTime(
    localNow.year,
    localNow.month,
    localNow.day,
  ).add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));
  final periodStart = DateTime(
    localNow.year,
    localNow.month,
    localNow.day,
  ).subtract(const Duration(days: 6));
  final recentCravings = cravings
      .where((entry) => _isWithin(entry.createdAt, periodStart, periodEnd))
      .toList();
  final recentSos = sosSessions
      .where((session) => _isWithin(session.startedAt, periodStart, periodEnd))
      .toList();

  final intensityTotal = recentCravings.fold<int>(
    0,
    (total, entry) => total + _intensity(entry),
  );
  final peakIntensity = recentCravings.fold<int>(0, (peak, entry) {
    final intensity = _intensity(entry);
    return intensity > peak ? intensity : peak;
  });
  var markedCleanDays = 0;
  for (var offset = 0; offset < 7; offset++) {
    final day = periodStart.add(Duration(days: offset));
    if (cleanDays[_dateKey(day)] == true) markedCleanDays++;
  }

  return WeeklyRecoverySummary(
    periodStart: periodStart,
    periodEnd: periodEnd,
    cravingCount: recentCravings.length,
    averageIntensity: recentCravings.isEmpty
        ? 0
        : intensityTotal / recentCravings.length,
    peakIntensity: peakIntensity,
    cleanDays: markedCleanDays,
    sosStarted: recentSos.length,
    sosCompleted: recentSos.where((session) => session.isCompleted).length,
  );
}

SosCompletionSummary sosCompletionSummary(
  Iterable<SosSession> sessions, {
  DateTime? since,
}) {
  final filtered = sessions
      .where((session) => since == null || !session.startedAt.isBefore(since))
      .toList();
  final completed = filtered.where((session) => session.isCompleted).toList();
  final validDurations = completed
      .map((session) => session.duration)
      .whereType<Duration>()
      .toList();
  Duration? averageDuration;
  if (validDurations.isNotEmpty) {
    final totalMicroseconds = validDurations.fold<int>(
      0,
      (total, duration) => total + duration.inMicroseconds,
    );
    averageDuration = Duration(
      microseconds: totalMicroseconds ~/ validDurations.length,
    );
  }
  DateTime? lastCompletedAt;
  for (final session in completed) {
    final completion = session.completedAt!;
    if (lastCompletedAt == null || completion.isAfter(lastCompletedAt)) {
      lastCompletedAt = completion;
    }
  }

  return SosCompletionSummary(
    started: filtered.length,
    completed: completed.length,
    averageDuration: averageDuration,
    lastCompletedAt: lastCompletedAt,
  );
}

class _BreakdownAccumulator {
  _BreakdownAccumulator(this.label);

  final String label;
  int count = 0;
  int totalIntensity = 0;
}

int _sortBreakdowns(InsightBreakdown a, InsightBreakdown b) {
  final countComparison = b.count.compareTo(a.count);
  return countComparison != 0
      ? countComparison
      : a.label.toLowerCase().compareTo(b.label.toLowerCase());
}

bool _isWithin(DateTime value, DateTime start, DateTime end) {
  final local = value.toLocal();
  return !local.isBefore(start) && !local.isAfter(end);
}

String _dateKey(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

int _intensity(CravingEntry entry) => entry.intensity.clamp(0, 10).toInt();
