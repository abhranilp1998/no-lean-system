import '../../recovery/domain/notification_policy.dart';

/// When the optional weekly recap notification fires: a weekday and a
/// minute of the local day.
class WeeklyRecapSlot {
  const WeeklyRecapSlot({required this.weekday, required this.minuteOfDay});

  /// [DateTime.monday] to [DateTime.sunday].
  final int weekday;
  final int minuteOfDay;

  @override
  bool operator ==(Object other) =>
      other is WeeklyRecapSlot &&
      other.weekday == weekday &&
      other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => Object.hash(weekday, minuteOfDay);

  @override
  String toString() => 'WeeklyRecapSlot($weekday, $minuteOfDay)';
}

/// Sunday at 6 PM, unless that lands inside quiet hours: then the first
/// minute after quiet hours end. The recap is never delivered while quiet
/// hours are on.
WeeklyRecapSlot weeklyRecapSlot(NotificationPrefs prefs) {
  const defaultMinute = 18 * 60;
  var weekday = DateTime.sunday;
  var minute = defaultMinute;
  if (prefs.quietHoursEnabled) {
    // Quiet hours repeat daily, so the weekday does not matter.
    final probe = DateTime(2026, 1, 4, minute ~/ 60, minute % 60);
    if (prefs.quietHours.contains(probe)) {
      minute = prefs.quietHours.endMinutes + 1;
      if (minute >= 24 * 60) {
        minute = 0;
        weekday = weekday == DateTime.sunday ? DateTime.monday : weekday + 1;
      }
    }
  }
  return WeeklyRecapSlot(weekday: weekday, minuteOfDay: minute);
}

/// The next time [slot] occurs strictly after [now] (local time).
DateTime nextWeeklyOccurrence(DateTime now, WeeklyRecapSlot slot) {
  var candidate = DateTime(
    now.year,
    now.month,
    now.day,
    slot.minuteOfDay ~/ 60,
    slot.minuteOfDay % 60,
  );
  while (candidate.weekday != slot.weekday || !candidate.isAfter(now)) {
    candidate = DateTime(
      candidate.year,
      candidate.month,
      candidate.day + 1,
      slot.minuteOfDay ~/ 60,
      slot.minuteOfDay % 60,
    );
  }
  return candidate;
}

/// Neutral on purpose: no numbers (a scheduled notification would be stale
/// by the time it fires) and no substance words. With private notifications
/// on, [NotificationPrefs.textFor] replaces it with the standard "Reminder".
const weeklyRecapNotificationTitle = 'YOUR WEEK';
const weeklyRecapNotificationBody =
    'Your weekly look back is ready. Open it when you have a moment.';
