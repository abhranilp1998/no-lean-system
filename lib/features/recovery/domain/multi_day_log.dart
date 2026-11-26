import 'dose_units.dart';
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

/// One dose on a picked day: the time it happened, plus optional per-dose
/// overrides of the shared type and amount.
///
/// A day can hold several slots (several doses). Every slot is saved as its
/// own independent relapse event with its own `occurredAt`.
class MultiDaySlot {
  const MultiDaySlot({
    required this.day,
    required this.hour,
    required this.minute,
    this.type,
    this.dose,
  });

  final DateTime day;
  final int hour;
  final int minute;

  /// Per-dose type; null means "same as the shared entry".
  final RelapseType? type;

  /// Per-dose amount; null means "same as the shared entry".
  final DoseAmount? dose;

  DateTime get occurredAt =>
      DateTime(day.year, day.month, day.day, hour, minute);

  bool get hasOverride => type != null || dose != null;

  MultiDaySlot withTime(int hour, int minute) => MultiDaySlot(
    day: day,
    hour: hour,
    minute: minute,
    type: type,
    dose: dose,
  );

  /// Replaces both overrides (pass null to go back to the shared value).
  MultiDaySlot withOverride({RelapseType? type, DoseAmount? dose}) =>
      MultiDaySlot(
        day: day,
        hour: hour,
        minute: minute,
        type: type,
        dose: dose,
      );
}

/// At most this many doses on one day. The overall save cap still applies.
const multiDayMaxDosesPerDay = 12;

/// Doses on [day], in time order.
List<MultiDaySlot> dosesOnDay(Iterable<MultiDaySlot> slots, DateTime day) {
  final d = dayOnly(day);
  return [
    for (final slot in slots)
      if (slot.day == d) slot,
  ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
}

/// The distinct picked days, oldest first.
List<DateTime> slotDays(Iterable<MultiDaySlot> slots) =>
    ({for (final s in slots) s.day}.toList()..sort());

/// Slots sorted by day, then time.
List<MultiDaySlot> sortedSlots(Iterable<MultiDaySlot> slots) =>
    List<MultiDaySlot>.of(slots)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

/// A slot whose exact minute is already used by another dose on the same
/// day, or null when every dose has its own time.
MultiDaySlot? firstDuplicateSlot(Iterable<MultiDaySlot> slots) {
  final seen = <DateTime>{};
  for (final slot in sortedSlots(slots)) {
    if (!seen.add(slot.occurredAt)) return slot;
  }
  return null;
}

/// True when [hour]:[minute] on [day] is used by a dose other than the one
/// at [ignoreIndex] in [slots].
bool timeTakenOnDay(
  List<MultiDaySlot> slots,
  DateTime day,
  int hour,
  int minute, {
  int? ignoreIndex,
}) {
  for (var i = 0; i < slots.length; i++) {
    if (i == ignoreIndex) continue;
    final s = slots[i];
    if (s.day == dayOnly(day) && s.hour == hour && s.minute == minute) {
      return true;
    }
  }
  return false;
}

/// Evenly spread default times for [count] doses in one day, as minutes
/// since midnight. One dose keeps the usual 9 PM; more are spread from 9 AM
/// to 9 PM (2 → 9 AM, 9 PM; 3 → 9 AM, 3 PM, 9 PM). When [latestMinute] is
/// given (today), nothing lands after it. Times are strictly increasing
/// whenever the window allows it.
List<int> defaultDoseMinutes(int count, {int? latestMinute}) {
  if (count <= 0) return const [];
  var hi = multiDayDefaultHour * 60 + multiDayDefaultMinute;
  if (latestMinute != null && latestMinute < hi) hi = latestMinute;
  if (count == 1) return [hi];
  var lo = 9 * 60;
  // Keep at least 15 minutes between doses when the window is short.
  if (hi - lo < (count - 1) * 15) lo = hi - (count - 1) * 15;
  if (lo < 0) lo = 0;
  final times = [
    for (var i = 0; i < count; i++) lo + ((hi - lo) * i / (count - 1)).round(),
  ];
  times[count - 1] = hi;
  for (var i = count - 2; i >= 0; i--) {
    if (times[i] >= times[i + 1]) times[i] = times[i + 1] - 1;
  }
  return times;
}

/// [count] default doses on [day] (today's are never in the future).
/// [carry] supplies per-dose overrides to keep, by position.
List<MultiDaySlot> defaultDosesForDay(
  DateTime day,
  int count, {
  required DateTime now,
  List<MultiDaySlot> carry = const [],
}) {
  final d = dayOnly(day);
  final isToday = d == dayOnly(now);
  final minutes = defaultDoseMinutes(
    count,
    latestMinute: isToday ? now.hour * 60 + now.minute : null,
  );
  return [
    for (var i = 0; i < minutes.length; i++)
      MultiDaySlot(
        day: d,
        hour: minutes[i] < 0 ? 0 : minutes[i] ~/ 60,
        minute: minutes[i] < 0 ? 0 : minutes[i] % 60,
        type: i < carry.length ? carry[i].type : null,
        dose: i < carry.length ? carry[i].dose : null,
      ),
  ];
}

/// A free time for one more dose on [day]: three hours after the latest
/// dose, else three hours before the earliest, else the first free minute
/// found by walking back from the latest. Never in the future. Null when
/// the day cannot take another dose.
MultiDaySlot? nextDoseSlot(
  Iterable<MultiDaySlot> slots,
  DateTime day, {
  required DateTime now,
}) {
  final d = dayOnly(day);
  final existing = dosesOnDay(slots, d);
  if (existing.length >= multiDayMaxDosesPerDay) return null;
  if (!isPickableDay(d, now: now)) return null;
  final used = {for (final s in existing) s.hour * 60 + s.minute};
  final limit = d == dayOnly(now) ? now.hour * 60 + now.minute : 24 * 60 - 1;
  int? pick;
  if (existing.isEmpty) {
    pick = defaultDoseMinutes(1, latestMinute: limit).first;
  } else {
    final last = existing.last.hour * 60 + existing.last.minute;
    final first = existing.first.hour * 60 + existing.first.minute;
    if (last + 180 <= limit) {
      pick = last + 180;
    } else if (first - 180 >= 0) {
      pick = first - 180;
    } else {
      for (var m = limit; m >= 0; m--) {
        if (!used.contains(m)) {
          pick = m;
          break;
        }
      }
    }
  }
  if (pick == null || pick < 0 || used.contains(pick)) return null;
  return MultiDaySlot(day: d, hour: pick ~/ 60, minute: pick % 60);
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

/// Copies the shared [template] to one entry per slot (dose). A slot's own
/// type or amount, when set, replaces the shared one for that dose only.
List<RelapseLogEntry> expandMultiDayEntries(
  RelapseLogEntry template,
  List<MultiDaySlot> slots,
) => [
  for (final slot in slots)
    template.withDoseOverride(
      occurredAt: slot.occurredAt,
      type: slot.type,
      dose: slot.dose,
    ),
];

/// "5 entries across 3 days".
String multiDayEntrySummary(Iterable<MultiDaySlot> slots) =>
    multiDayEntrySummaryCounts(slots.length, slotDays(slots).length);

String multiDayEntrySummaryCounts(int n, int days) {
  return '$n ${n == 1 ? 'entry' : 'entries'} across $days ${days == 1 ? 'day' : 'days'}';
}

/// Whether saving [entries] moves the lean/codeine clean timer. Benzo-only
/// entries are kept for safety checks but leave lean clean time alone; every
/// other type (lean, partial, mixed, alcohol, other) still resets it.
bool entriesResetLeanTimer(Iterable<RelapseLogEntry> entries) =>
    entries.any((entry) => entry.effectiveType != RelapseType.benzo);
