import '../../recovery/domain/craving_entry.dart';
import '../../recovery/domain/recovery_event.dart';
import '../../recovery/domain/risk_window.dart';
import '../../recovery/domain/sos_session.dart';

/// Patterns stay hidden until there is enough data to be honest about them.
const minimumSignalsForPattern = 5;

/// A trigger or time band must repeat at least this often to be called out.
const minimumRepeatsForPattern = 3;

/// One craving or relapse, reduced to what pattern detection needs.
class RiskSignal {
  const RiskSignal({
    required this.at,
    required this.isRelapse,
    this.triggers = const [],
    this.intensity,
  });

  final DateTime at;
  final bool isRelapse;
  final List<String> triggers;

  /// Craving intensity 0–10; null for relapses.
  final int? intensity;
}

/// Merges cravings and relapse events into one signal list. Relapse context
/// tags count as triggers.
List<RiskSignal> riskSignals({
  required Iterable<CravingEntry> cravings,
  Iterable<RecoveryEvent> relapses = const [],
}) {
  final signals = <RiskSignal>[
    for (final entry in cravings)
      RiskSignal(
        at: entry.createdAt,
        isRelapse: false,
        triggers: [if (entry.trigger.trim().isNotEmpty) entry.trigger.trim()],
        intensity: _intensity(entry),
      ),
  ];
  for (final event in relapses) {
    if (event.type != RecoveryEventType.relapse) continue;
    final tags = event.metadata['contextTags'];
    signals.add(
      RiskSignal(
        at: event.timestamp,
        isRelapse: true,
        triggers: tags is List
            ? tags
                  .whereType<String>()
                  .map((tag) => tag.trim())
                  .where((tag) => tag.isNotEmpty)
                  .toSet()
                  .toList()
            : const [],
      ),
    );
  }
  return signals;
}

/// Trigger breakdown across cravings and relapses. Untagged relapses are left
/// out (no trigger was recorded); untagged cravings count as "Other".
/// [InsightBreakdown.averageIntensity] averages cravings only.
List<InsightBreakdown> signalTriggerBreakdown(Iterable<RiskSignal> signals) {
  final groups = <String, _BreakdownAccumulator>{};
  var total = 0;
  for (final signal in signals) {
    final labels = signal.triggers.isEmpty
        ? (signal.isRelapse ? const <String>[] : const ['Other'])
        : signal.triggers;
    if (labels.isEmpty) continue;
    total++;
    for (final label in labels) {
      final group = groups.putIfAbsent(
        label.toLowerCase(),
        () => _BreakdownAccumulator(label),
      );
      group.count++;
      if (signal.isRelapse) {
        group.relapses++;
      } else {
        group
          ..cravings += 1
          ..totalIntensity += signal.intensity ?? 0;
      }
    }
  }
  if (total == 0) return const [];
  final result = groups.values.map((group) => group.toBreakdown(total)).toList()
    ..sort(_sortBreakdowns);
  return List.unmodifiable(result);
}

/// Fixed time-of-day bands across cravings and relapses.
List<InsightBreakdown> signalTimeBreakdown(Iterable<RiskSignal> signals) {
  final groups = {
    for (final label in _bandLabels) label: _BreakdownAccumulator(label),
  };
  var total = 0;
  for (final signal in signals) {
    final group = groups[_bandFor(signal.at)]!..count += 1;
    if (signal.isRelapse) {
      group.relapses++;
    } else {
      group
        ..cravings += 1
        ..totalIntensity += signal.intensity ?? 0;
    }
    total++;
  }
  if (total == 0) return const [];
  return List.unmodifiable(
    groups.values.map((group) => group.toBreakdown(total)),
  );
}

class RiskWindowShare {
  const RiskWindowShare({
    required this.window,
    required this.total,
    required this.inWindow,
    required this.relapsesInWindow,
  });

  final RiskWindow window;
  final int total;
  final int inWindow;
  final int relapsesInWindow;

  double get ratio => total == 0 ? 0 : inWindow / total;
  int get percent => (ratio * 100).round();
}

RiskWindowShare riskWindowShare(
  Iterable<RiskSignal> signals,
  RiskWindow window,
) {
  var total = 0;
  var inWindow = 0;
  var relapses = 0;
  for (final signal in signals) {
    total++;
    if (window.contains(signal.at.toLocal())) {
      inWindow++;
      if (signal.isRelapse) relapses++;
    }
  }
  return RiskWindowShare(
    window: window,
    total: total,
    inWindow: inWindow,
    relapsesInWindow: relapses,
  );
}

class RelapseCost {
  const RelapseCost({required this.relapseDays, required this.dailySpend});

  /// Distinct calendar days with at least one relapse in the period.
  final int relapseDays;
  final double dailySpend;

  double get amount => relapseDays * dailySpend;
}

/// Estimated money lost to relapses over the last [days] days: each relapse
/// day is priced at the user's tracked daily spend.
RelapseCost relapseCost({
  required Iterable<RecoveryEvent> relapses,
  required double dailySpend,
  required DateTime now,
  int days = 30,
}) {
  final since = now.subtract(Duration(days: days));
  final dates = <String>{
    for (final event in relapses)
      if (event.type == RecoveryEventType.relapse &&
          event.timestamp.isAfter(since) &&
          !event.timestamp.isAfter(now))
        _dateKey(event.timestamp),
  };
  return RelapseCost(
    relapseDays: dates.length,
    dailySpend: dailySpend < 0 ? 0 : dailySpend,
  );
}

class InsightBreakdown {
  const InsightBreakdown({
    required this.label,
    required this.count,
    required this.ratio,
    required this.averageIntensity,
    this.relapseCount = 0,
  });

  final String label;
  final int count;
  final double ratio;

  /// Average craving intensity (relapses carry no intensity).
  final double averageIntensity;

  /// How many of [count] were relapses rather than cravings.
  final int relapseCount;
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
  Iterable<RecoveryEvent> relapses = const [],
  RiskWindow riskWindow = const RiskWindow.defaultWindow(),
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final entries = cravings.toList();
  final relapseEvents = relapses
      .where((event) => event.type == RecoveryEventType.relapse)
      .toList();
  final sessions = sosSessions.toList();
  final signals = riskSignals(cravings: entries, relapses: relapseEvents);
  final enoughData = signals.length >= minimumSignalsForPattern;
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

  if (enoughData) {
    final triggers = signalTriggerBreakdown(signals);
    final tagged = signals
        .where((signal) => signal.triggers.isNotEmpty || !signal.isRelapse)
        .length;
    if (triggers.isNotEmpty &&
        triggers.first.count >= minimumRepeatsForPattern &&
        tagged >= minimumSignalsForPattern) {
      final dominant = triggers.first;
      final relapseLine = dominant.relapseCount == 0
          ? ''
          : ' ${_plural(dominant.relapseCount, 'relapse')} came out of it.';
      results.add(
        PatternActionInsight(
          title: '${dominant.label.toUpperCase()} OWNS THE LOOP',
          body:
              '${(dominant.ratio * 100).round()}% of your $tagged logged signals point here.$relapseLine Before the next exposure: change location, remove the payment path, and open SOS before negotiating.',
          evidence:
              '${dominant.count} OF $tagged SIGNALS // ${dominant.relapseCount} RELAPSE${dominant.relapseCount == 1 ? '' : 'S'}',
          actionLabel: 'PRACTICE SOS',
          action: PatternActionKind.openSos,
        ),
      );
    }

    final share = riskWindowShare(signals, riskWindow);
    final bands = signalTimeBreakdown(signals);
    final topBand = bands.reduce((a, b) => a.count >= b.count ? a : b);
    final relapsesNote = share.relapsesInWindow == 0
        ? ''
        : ' ${_plural(share.relapsesInWindow, 'relapse')} landed inside it.';
    if (share.ratio >= .5 && share.inWindow >= minimumRepeatsForPattern) {
      results.add(
        PatternActionInsight(
          title: 'YOUR ${share.window.label} WINDOW IS CONFIRMED',
          body:
              '${share.percent}% of your ${share.total} cravings and relapses hit inside it.$relapsesNote Start protection 15 minutes before it opens and keep the window lock armed.',
          evidence:
              '${share.inWindow} OF ${share.total} SIGNALS // ${share.percent}% IN WINDOW',
          actionLabel: 'TUNE RISK WINDOW',
          action: PatternActionKind.editRiskWindow,
        ),
      );
    } else if (topBand.count >= minimumRepeatsForPattern &&
        topBand.count > share.inWindow) {
      results.add(
        PatternActionInsight(
          title: 'YOUR RISK WINDOW IS MISPLACED',
          body:
              'Only ${share.percent}% of your ${share.total} signals fell inside ${share.window.label}, but ${(topBand.ratio * 100).round()}% hit ${topBand.label}. Move the window to where the data is.',
          evidence:
              '${topBand.count} OF ${share.total} IN ${topBand.label} // ${share.inWindow} IN WINDOW',
          actionLabel: 'MOVE RISK WINDOW',
          action: PatternActionKind.editRiskWindow,
        ),
      );
    }
  }

  final cost = relapseCost(
    relapses: relapseEvents,
    dailySpend: dailySpend,
    now: current,
  );
  if (cost.relapseDays > 0 && cost.dailySpend > 0) {
    results.add(
      PatternActionInsight(
        title: 'RELAPSES COST ${cost.amount.toStringAsFixed(0)} THIS MONTH',
        body:
            '${_plural(cost.relapseDays, 'relapse day')} in the last 30 days at your tracked ${cost.dailySpend.toStringAsFixed(0)}/day. That is money the clean days kept. Lock today so the next 24 hours add to the other column.',
        evidence:
            '${cost.relapseDays} DAY${cost.relapseDays == 1 ? '' : 'S'} × ${cost.dailySpend.toStringAsFixed(0)} // ESTIMATE FROM DAILY SPEND',
        actionLabel: 'LOCK TODAY',
        action: PatternActionKind.pledge,
      ),
    );
  }

  final sos = sosCompletionSummary(sessions);
  if (sos.started >= 2 && sos.completionRate < .6) {
    results.add(
      PatternActionInsight(
        title: 'THE OVERRIDE IS BEING CUT SHORT',
        body:
            'Only ${sos.completed} of ${sos.started} SOS runs reached the end. Rehearse the full sequence while calm so it is familiar under pressure.',
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

  if (!enoughData) {
    results.add(
      PatternActionInsight(
        title: 'BUILD THE SIGNAL BASELINE',
        body:
            '${signals.length} of $minimumSignalsForPattern signals logged. Trigger and timing patterns stay hidden until there is enough data to be honest. Log the hour, intensity and real trigger every time.',
        evidence:
            '${signals.length}/$minimumSignalsForPattern SIGNALS // PATTERNS LOCKED',
        actionLabel: 'LOG A CRAVING',
        action: PatternActionKind.logCraving,
      ),
    );
  } else if (results.isEmpty) {
    results.add(
      PatternActionInsight(
        title: 'NO DOMINANT PATTERN YET',
        body:
            '${signals.length} signals logged and none repeats $minimumRepeatsForPattern+ times in one trigger or band. Keep logging the real trigger, not a guess.',
        evidence: '${signals.length} SIGNALS // NO REPEAT ABOVE THRESHOLD',
        actionLabel: 'LOG A CRAVING',
        action: PatternActionKind.logCraving,
      ),
    );
  }

  return List.unmodifiable(results.take(4));
}

String _plural(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';

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
  int cravings = 0;
  int relapses = 0;
  int totalIntensity = 0;

  InsightBreakdown toBreakdown(int total) => InsightBreakdown(
    label: label,
    count: count,
    ratio: count / total,
    averageIntensity: cravings == 0 ? 0 : totalIntensity / cravings,
    relapseCount: relapses,
  );
}

const _bandLabels = [
  'OVERNIGHT / 00-05',
  'MORNING / 06-11',
  'AFTERNOON / 12-16',
  'EVENING / 17-23',
];

String _bandFor(DateTime at) => switch (at.toLocal().hour) {
  < 6 => _bandLabels[0],
  < 12 => _bandLabels[1],
  < 17 => _bandLabels[2],
  _ => _bandLabels[3],
};

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
