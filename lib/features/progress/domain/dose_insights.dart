import '../../recovery/domain/dose_units.dart';
import '../../recovery/domain/recovery_event.dart';
import '../../recovery/domain/relapse_log_entry.dart';

/// Dose escalation threshold: the latest dose is at least 20% above the
/// average of the previous ones.
const escalationRatio = 1.2;

/// Previous doses averaged for the escalation baseline.
const escalationBaselineSize = 3;

/// Previous doses needed before escalation is judged at all.
const escalationMinimumBaseline = 2;

/// One relapse event read for dose maths. Legacy events have no type or
/// dose; they still count as relapses.
class DoseRecord {
  DoseRecord(this.event)
    : type = RelapseTypeLabel.fromName(event.metadata['relapseType']),
      dose = DoseAmount.fromMetadata(event.metadata),
      cost = (event.metadata['cost'] as num?)?.toDouble(),
      stress = event.metadata['stress'] as int?;

  final RecoveryEvent event;
  final RelapseType? type;
  final DoseAmount? dose;
  final double? cost;
  final int? stress;

  DateTime get at => event.timestamp;
}

List<DoseRecord> doseRecords(Iterable<RecoveryEvent> events) => [
  for (final event in events)
    if (event.type == RecoveryEventType.relapse) DoseRecord(event),
]..sort((a, b) => a.at.compareTo(b.at));

/// Totals for one relapse type. Volume (ml) and counts (tablets, drinks)
/// are kept apart: a tablet is never added to millilitres.
class RelapseTypeStats {
  RelapseTypeStats(this.type);

  /// Null groups legacy relapses logged without a type.
  final RelapseType? type;
  int count = 0;
  DateTime? last;
  double totalMl = 0;
  int volumeDoses = 0;
  final Map<DoseUnit, double> countTotals = {};
  double realCost = 0;
  int costedCount = 0;

  String get label => type?.label ?? 'UNTYPED (LEGACY)';
  double? get averageMl => volumeDoses == 0 ? null : totalMl / volumeDoses;
}

/// Per-type breakdown, most frequent first.
List<RelapseTypeStats> relapseTypeStats(Iterable<RecoveryEvent> events) {
  final byType = <RelapseType?, RelapseTypeStats>{};
  for (final record in doseRecords(events)) {
    final stats = byType.putIfAbsent(
      record.type,
      () => RelapseTypeStats(record.type),
    );
    stats.count++;
    stats.last = record.at;
    final dose = record.dose;
    if (dose != null) {
      if (dose.amountMl != null) {
        stats.totalMl += dose.amountMl!;
        stats.volumeDoses++;
      } else {
        stats.countTotals[dose.unit] =
            (stats.countTotals[dose.unit] ?? 0) + dose.amount;
      }
    }
    if (record.cost != null) {
      stats.realCost += record.cost!;
      stats.costedCount++;
    }
  }
  return byType.values.toList()..sort((a, b) => b.count.compareTo(a.count));
}

/// The comparable measure of a dose: ml for volume, otherwise the count of
/// its own unit. Only doses with the same [key] are ever compared.
({String key, double value, String unitLabel})? _measure(DoseAmount dose) {
  if (dose.amountMl != null) {
    return (key: 'ml', value: dose.amountMl!, unitLabel: 'ml');
  }
  return (key: dose.unit.name, value: dose.amount, unitLabel: dose.unit.label);
}

class DoseEscalation {
  const DoseEscalation({
    required this.type,
    required this.unitKey,
    required this.unitLabel,
    required this.latest,
    required this.baseline,
    required this.baselineCount,
    required this.latestEvent,
  });

  final RelapseType? type;

  /// `ml` for volume doses, else the count unit (`tablet`, `drink`).
  final String unitKey;
  final String unitLabel;
  final double latest;
  final double baseline;
  final int baselineCount;
  final RecoveryEvent latestEvent;

  double get ratio => latest / baseline;
  int get percentUp => ((ratio - 1) * 100).round();

  String format(double value) =>
      unitKey == 'ml' ? formatMl(value) : '${formatAmount(value)} $unitLabel';
}

/// Latest dose vs the average of up to 3 previous doses of the same type
/// and comparable unit; flagged at >= 20% higher. Needs 2+ previous doses,
/// and the latest must be within [recent] of [now].
List<DoseEscalation> doseEscalations(
  Iterable<RecoveryEvent> events, {
  required DateTime now,
  Duration recent = const Duration(days: 30),
}) {
  final series = <(RelapseType?, String), List<(DoseRecord, double, String)>>{};
  for (final record in doseRecords(events)) {
    final dose = record.dose;
    if (dose == null) continue;
    final measure = _measure(dose)!;
    series.putIfAbsent((record.type, measure.key), () => []).add((
      record,
      measure.value,
      measure.unitLabel,
    ));
  }
  final results = <DoseEscalation>[];
  for (final entry in series.entries) {
    final list = entry.value;
    if (list.length < escalationMinimumBaseline + 1) continue;
    final latest = list.last;
    if (now.difference(latest.$1.at) > recent) continue;
    final previous = list
        .sublist(0, list.length - 1)
        .reversed
        .take(escalationBaselineSize)
        .toList();
    final baseline =
        previous.fold<double>(0, (sum, item) => sum + item.$2) /
        previous.length;
    if (baseline <= 0 || latest.$2 < baseline * escalationRatio) continue;
    results.add(
      DoseEscalation(
        type: entry.key.$1,
        unitKey: entry.key.$2,
        unitLabel: latest.$3,
        latest: latest.$2,
        baseline: baseline,
        baselineCount: previous.length,
        latestEvent: latest.$1.event,
      ),
    );
  }
  results.sort((a, b) => b.ratio.compareTo(a.ratio));
  return results;
}

class SameDayRepeat {
  const SameDayRepeat({required this.day, required this.count, this.totalMl});

  final DateTime day;
  final int count;

  /// Total ml that day when any volume dose was logged.
  final double? totalMl;
}

/// Calendar days in the last [days] days with 2+ relapses (repeat dosing).
List<SameDayRepeat> sameDayRepeats(
  Iterable<RecoveryEvent> events, {
  required DateTime now,
  int days = 30,
}) {
  final since = now.subtract(Duration(days: days));
  final byDay = <DateTime, List<DoseRecord>>{};
  for (final record in doseRecords(events)) {
    if (record.at.isBefore(since) || record.at.isAfter(now)) continue;
    final local = record.at.toLocal();
    byDay
        .putIfAbsent(DateTime(local.year, local.month, local.day), () => [])
        .add(record);
  }
  return [
    for (final entry in byDay.entries)
      if (entry.value.length >= 2)
        SameDayRepeat(
          day: entry.key,
          count: entry.value.length,
          totalMl: entry.value.any((r) => r.dose?.amountMl != null)
              ? entry.value.fold<double>(
                  0,
                  (sum, r) => sum + (r.dose?.amountMl ?? 0),
                )
              : null,
        ),
  ]..sort((a, b) => b.day.compareTo(a.day));
}

/// Recent logs that point to high need right now.
class HighNeedSignal {
  const HighNeedSignal({required this.reasons, required this.evidenceCount});

  final List<String> reasons;
  final int evidenceCount;
}

/// High need in the last 48 hours: any stress 5, two or more logs at
/// stress 4+, or stress 4+ alongside a craving that got stronger on recheck.
HighNeedSignal? highNeedSignal(
  Iterable<RecoveryEvent> events, {
  required DateTime now,
  Duration window = const Duration(hours: 48),
}) {
  final since = now.subtract(window);
  final recent = events
      .where((e) => e.timestamp.isAfter(since) && !e.timestamp.isAfter(now))
      .toList();
  final stressed = recent
      .where(
        (e) =>
            (e.type == RecoveryEventType.craving ||
                e.type == RecoveryEventType.relapse) &&
            e.metadata['stress'] is int,
      )
      .toList();
  final maxStress = stressed.fold<int>(
    0,
    (max, e) =>
        (e.metadata['stress'] as int) > max ? e.metadata['stress'] as int : max,
  );
  final high = stressed.where((e) => (e.metadata['stress'] as int) >= 4);
  final stronger = recent
      .where(
        (e) =>
            e.type == RecoveryEventType.cravingCheck &&
            e.metadata['outcome'] == 'stronger',
      )
      .length;
  final reasons = <String>[
    if (maxStress == 5) 'stress logged at 5/5',
    if (high.length >= 2) '${high.length} logs at stress 4+',
    if (high.isNotEmpty && stronger > 0)
      '$stronger craving${stronger == 1 ? '' : 's'} got stronger on recheck',
  ];
  if (reasons.isEmpty) return null;
  return HighNeedSignal(
    reasons: reasons,
    evidenceCount: high.length + stronger,
  );
}

/// Craving intensity under high stress (4-5) vs low stress (1-2).
class StressIntensityPattern {
  const StressIntensityPattern({
    required this.highAverage,
    required this.lowAverage,
    required this.highCount,
    required this.lowCount,
  });

  final double highAverage;
  final double lowAverage;
  final int highCount;
  final int lowCount;
}

/// Needs 3+ cravings in each group and high-stress intensity >= 1.2x.
StressIntensityPattern? stressIntensityPattern(Iterable<RecoveryEvent> events) {
  final high = <int>[];
  final low = <int>[];
  for (final event in events) {
    if (event.type != RecoveryEventType.craving) continue;
    final stress = event.metadata['stress'];
    final intensity = event.metadata['intensity'];
    if (stress is! int || intensity is! int) continue;
    if (stress >= 4) high.add(intensity);
    if (stress <= 2) low.add(intensity);
  }
  if (high.length < 3 || low.length < 3) return null;
  double avg(List<int> values) =>
      values.reduce((a, b) => a + b) / values.length;
  final highAverage = avg(high);
  final lowAverage = avg(low);
  if (highAverage < lowAverage * escalationRatio) return null;
  return StressIntensityPattern(
    highAverage: highAverage,
    lowAverage: lowAverage,
    highCount: high.length,
    lowCount: low.length,
  );
}
