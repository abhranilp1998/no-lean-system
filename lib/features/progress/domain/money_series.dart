import '../../../core/utils/formatters.dart';
import '../../recovery/domain/recovery_event.dart';

/// Running totals at the end of one calendar day.
class MoneyPoint {
  const MoneyPoint({
    required this.day,
    required this.saved,
    required this.lost,
    this.realLost = 0,
  });

  final DateTime day;
  final double saved;

  /// Everything lost so far: recorded costs plus estimated relapse days.
  final double lost;

  /// The part of [lost] the user actually recorded as a cost.
  final double realLost;

  double get estimatedLost => lost - realLost;
}

/// Cumulative money kept vs. spent, one point per local day from the first
/// recorded day to today. A relapse day with recorded costs loses exactly
/// those costs; a relapse day without one is estimated at [dailySpend]
/// (labelled in the UI). Every other day keeps [dailySpend]. Today counts
/// only the part of the day that has passed. Past spend changes are not
/// recorded, so the current figure applies to all history. With no daily
/// spend set, recorded costs are still charted.
List<MoneyPoint> cumulativeMoneySeries({
  required Iterable<RecoveryEvent> events,
  required double dailySpend,
  required DateTime now,
}) {
  final spend = dailySpend.isFinite && dailySpend > 0 ? dailySpend : 0.0;
  final realByDay = <String, double>{};
  for (final event in events) {
    final cost = event.metadata['cost'];
    if (event.type == RecoveryEventType.relapse && cost is num) {
      final key = dateKey(event.timestamp.toLocal());
      realByDay[key] = (realByDay[key] ?? 0) + cost;
    }
  }
  if (spend == 0 && realByDay.isEmpty) return const [];
  final relapseDays = <String>{};
  DateTime? first;
  for (final event in events) {
    final DateTime day;
    if (event.type == RecoveryEventType.daySummary) {
      day = DateTime.parse(event.metadata['date'] as String);
      if (event.metadata['clean'] == false) relapseDays.add(dateKey(day));
    } else {
      final local = event.timestamp.toLocal();
      day = DateTime(local.year, local.month, local.day);
      if (event.type == RecoveryEventType.relapse) {
        relapseDays.add(dateKey(day));
      }
    }
    if (first == null || day.isBefore(first)) first = day;
  }
  final today = DateTime(now.year, now.month, now.day);
  if (first == null || first.isAfter(today)) return const [];

  final points = <MoneyPoint>[];
  var saved = 0.0;
  var lost = 0.0;
  var realLost = 0.0;
  // Calendar stepping (not +24h) so DST-free and DST zones both work.
  for (
    var day = first;
    !day.isAfter(today);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    final key = dateKey(day);
    final real = realByDay[key];
    if (real != null) {
      lost += real;
      realLost += real;
    } else if (relapseDays.contains(key)) {
      lost += spend;
    } else if (day == today) {
      final elapsed = now.difference(today).inMinutes / Duration.minutesPerDay;
      saved += spend * elapsed.clamp(0, 1);
    } else {
      saved += spend;
    }
    points.add(
      MoneyPoint(day: day, saved: saved, lost: lost, realLost: realLost),
    );
  }
  return points;
}
