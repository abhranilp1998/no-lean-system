import 'relapse_log_entry.dart';

/// Multi-day catch-up logging: pick several past days, describe them once,
/// and save one independent relapse event per day.
///
/// Each day keeps its own `occurredAt` (the event timestamp), so the clean
/// timer, heat map and milestones read the real day, and each entry can be
/// edited or deleted on its own later. `recordedAt` is the save moment.

/// Default time for a picked day when the user does not choose one.
/// Evening is when most catch-up entries happened for this app's users and
/// it matches the default risk window better than midnight would.
const multiDayDefaultHour = 21;
const multiDayDefaultMinute = 0;

/// The controller writes at most this many relapse events per save.
const multiDayMaxDays = 50;

/// Metadata flag stored on every event written by a multi-day save.
const multiDayMetadataKey = 'multiDay';

DateTime dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// True when [day] can be picked: today or earlier, and not before 2000.
bool isPickableDay(DateTime day, {required DateTime now}) {
  final d = dayOnly(day);
  return !d.isAfter(dayOnly(now)) && !d.isBefore(DateTime(2000));
}

/// One picked day with the time the event happened on it.
class MultiDaySlot {
  const MultiDaySlot({
    required this.day,
    required this.hour,
    required this.minute,
  });

  final DateTime day;
  final int hour;
  final int minute;

  DateTime get occurredAt =>
      DateTime(day.year, day.month, day.day, hour, minute);

  MultiDaySlot withTime(int hour, int minute) =>
      MultiDaySlot(day: day, hour: hour, minute: minute);
}

/// Builds sorted, de-duplicated slots for [days] at [hour]:[minute].
///
/// Future days are dropped. A slot for today whose time is still ahead is
/// moved back to now (rounded down to the minute) so nothing is ever saved
/// in the future.
List<MultiDaySlot> buildMultiDaySlots(
  Iterable<DateTime> days, {
  required DateTime now,
  int hour = multiDayDefaultHour,
  int minute = multiDayDefaultMinute,
}) {
  final unique = <DateTime>{
    for (final day in days)
      if (isPickableDay(day, now: now)) dayOnly(day),
  }.toList()..sort();
  return [
    for (final day in unique)
      clampSlotToNow(MultiDaySlot(day: day, hour: hour, minute: minute), now),
  ];
}

MultiDaySlot clampSlotToNow(MultiDaySlot slot, DateTime now) {
  if (!slot.occurredAt.isAfter(now)) return slot;
  return slot.withTime(now.hour, now.minute);
}

/// The last [count] days ending today (or yesterday when [includeToday] is
/// false), oldest first.
List<DateTime> lastDays(
  int count, {
  required DateTime now,
  bool includeToday = true,
}) {
  final end = dayOnly(now).subtract(Duration(days: includeToday ? 0 : 1));
  return [
    for (var i = count - 1; i >= 0; i--)
      DateTime(end.year, end.month, end.day - i),
  ];
}

/// Copies the shared [template] to one entry per slot.
List<RelapseLogEntry> expandMultiDayEntries(
  RelapseLogEntry template,
  List<MultiDaySlot> slots,
) => [for (final slot in slots) template.copyWith(occurredAt: slot.occurredAt)];

/// Whether saving [entries] moves the lean/codeine clean timer. Benzo-only
/// entries are kept for safety checks but leave lean clean time alone; every
/// other type (lean, partial, mixed, alcohol, other) still resets it.
bool entriesResetLeanTimer(Iterable<RelapseLogEntry> entries) =>
    entries.any((entry) => entry.effectiveType != RelapseType.benzo);
