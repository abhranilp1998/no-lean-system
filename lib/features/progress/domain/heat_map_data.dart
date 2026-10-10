import '../../../core/utils/formatters.dart';
import '../../recovery/domain/dose_units.dart';
import '../../recovery/domain/recovery_event.dart';

/// What a heat-map cell measures.
enum HeatMapMode { days, count, amount, cost, stress }

extension HeatMapModeInfo on HeatMapMode {
  String get label => switch (this) {
    HeatMapMode.days => 'DAYS',
    HeatMapMode.count => 'COUNT',
    HeatMapMode.amount => 'AMOUNT',
    HeatMapMode.cost => 'COST',
    HeatMapMode.stress => 'STRESS',
  };

  String get description => switch (this) {
    HeatMapMode.days => 'Clean vs relapse days',
    HeatMapMode.count => 'Cravings + relapses logged per day',
    HeatMapMode.amount =>
      'ml per day (ml, L and bottles; tablets/drinks excluded)',
    HeatMapMode.cost => 'Recorded ₹ per day',
    HeatMapMode.stress => 'Highest stress logged per day (1-5)',
  };

  /// Display of one day's value; rounding is for display only.
  String format(double value) => switch (this) {
    HeatMapMode.days || HeatMapMode.count => '${value.round()}',
    HeatMapMode.amount => formatMl(value),
    HeatMapMode.cost => money(value),
    HeatMapMode.stress => '${value.round()}/5',
  };
}

/// Per-day values keyed by [dateKey]. Days with nothing logged are absent.
/// For [HeatMapMode.days] the value is the number of relapses that day.
Map<String, double> heatMapValues(
  HeatMapMode mode,
  Iterable<RecoveryEvent> events,
) {
  final values = <String, double>{};
  void add(String key, double value) =>
      values[key] = (values[key] ?? 0) + value;
  for (final event in events) {
    final key = dateKey(event.timestamp.toLocal());
    final isRelapse = event.type == RecoveryEventType.relapse;
    final isCraving = event.type == RecoveryEventType.craving;
    switch (mode) {
      case HeatMapMode.days:
        if (isRelapse) add(key, 1);
      case HeatMapMode.count:
        if (isRelapse || isCraving) add(key, 1);
      case HeatMapMode.amount:
        final ml = isRelapse
            ? DoseAmount.fromMetadata(event.metadata)?.amountMl
            : null;
        if (ml != null) add(key, ml);
      case HeatMapMode.cost:
        final cost = event.metadata['cost'];
        if (isRelapse && cost is num) add(key, cost.toDouble());
      case HeatMapMode.stress:
        final stress = event.metadata['stress'];
        if ((isRelapse || isCraving) && stress is int) {
          values[key] = (values[key] ?? 0) < stress
              ? stress.toDouble()
              : values[key]!;
        }
    }
  }
  return values;
}

/// One weekday's aggregate over the lookback period.
class WeekdayStat {
  const WeekdayStat({
    required this.weekday,
    required this.value,
    required this.days,
  });

  /// DateTime.monday (1) .. DateTime.sunday (7).
  final int weekday;

  /// Sum for count/amount/cost/days; average of daily max for stress.
  final double value;

  /// Days that contributed a value.
  final int days;

  String get label =>
      const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][weekday - 1];
}

class WeekdaySummary {
  const WeekdaySummary({
    required this.mode,
    required this.stats,
    required this.dataDays,
  });

  final HeatMapMode mode;
  final List<WeekdayStat> stats;

  /// Distinct days with data in the period.
  final int dataDays;

  /// Peak weekday, or null when there is too little data to call one
  /// (fewer than 5 days with data, or a tie at the top).
  WeekdayStat? get peak {
    if (dataDays < 5) return null;
    final sorted = [...stats]..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.first.value <= 0 || sorted.first.value == sorted[1].value) {
      return null;
    }
    return sorted.first;
  }
}

/// Weekday totals for [mode] over the last [weeks] weeks.
WeekdaySummary weekdaySummary(
  HeatMapMode mode,
  Iterable<RecoveryEvent> events, {
  required DateTime now,
  int weeks = 12,
}) {
  final since = DateTime(now.year, now.month, now.day - weeks * 7);
  final values = heatMapValues(
    mode,
    events.where(
      (e) => !e.timestamp.isBefore(since) && !e.timestamp.isAfter(now),
    ),
  );
  final sums = List<double>.filled(7, 0);
  final days = List<int>.filled(7, 0);
  for (final entry in values.entries) {
    final weekday = DateTime.parse(entry.key).weekday;
    sums[weekday - 1] += entry.value;
    days[weekday - 1]++;
  }
  return WeekdaySummary(
    mode: mode,
    dataDays: values.length,
    stats: [
      for (var i = 0; i < 7; i++)
        WeekdayStat(
          weekday: i + 1,
          value: mode == HeatMapMode.stress && days[i] > 0
              ? sums[i] / days[i]
              : sums[i],
          days: days[i],
        ),
    ],
  );
}
