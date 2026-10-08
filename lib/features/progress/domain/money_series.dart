import '../../../core/utils/formatters.dart';
import '../../recovery/domain/recovery_event.dart';

/// Running totals at the end of one calendar day.
class MoneyPoint {
  const MoneyPoint({
    required this.day,
    required this.saved,
    required this.lost,
  });

  final DateTime day;
  final double saved;
  final double lost;
}

/// Cumulative money kept vs. spent, one point per local day from the first
/// recorded day to today. It is an estimate with one assumption, labelled in
/// the UI: every relapse day cost one [dailySpend], every other day kept it.
/// Today counts only the part of the day that has passed. Past spend changes
/// are not recorded, so the current figure applies to all history.
List<MoneyPoint> cumulativeMoneySeries({
  required Iterable<RecoveryEvent> events,
  required double dailySpend,
  required DateTime now,
}) {
  if (dailySpend <= 0 || !dailySpend.isFinite) return const [];
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
  // Calendar stepping (not +24h) so DST-free and DST zones both work.
  for (
    var day = first;
    !day.isAfter(today);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    if (relapseDays.contains(dateKey(day))) {
      lost += dailySpend;
    } else if (day == today) {
      final elapsed = now.difference(today).inMinutes / Duration.minutesPerDay;
      saved += dailySpend * elapsed.clamp(0, 1);
    } else {
      saved += dailySpend;
    }
    points.add(MoneyPoint(day: day, saved: saved, lost: lost));
  }
  return points;
}
