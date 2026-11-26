import '../../recovery/domain/notification_policy.dart';
import '../../recovery/domain/recovery_event.dart';
import 'bundled_dates.dart';

/// How an upcoming high-risk date was sourced.
enum HighRiskKind { bundled, custom, payday, weekday }

/// Why the user added a personal date.
enum CustomDateKind { birthday, lossAnniversary, exam, other }

extension CustomDateKindLabel on CustomDateKind {
  String get label => switch (this) {
    CustomDateKind.birthday => 'Birthday',
    CustomDateKind.lossAnniversary => 'Anniversary of a loss',
    CustomDateKind.exam => 'Exam / result day',
    CustomDateKind.other => 'Other',
  };
}

/// A named festival with explicit calendar days (never computed).
class BundledFestival {
  const BundledFestival({
    required this.id,
    required this.name,
    required this.blurb,
    required this.dates,
    this.spanDays = 1,
  });

  final String id;
  final String name;
  final String blurb;
  final List<String> dates;

  /// Inclusive length of the festival starting at each listed day.
  final int spanDays;

  List<DateTime> get parsedDates =>
      dates.map(parseDateOnly).toList(growable: false);
}

/// A user-added date: annual (birthday, anniversary) or one-off (exam).
class CustomHighRiskDate {
  const CustomHighRiskDate({
    required this.id,
    required this.name,
    required this.kind,
    this.month,
    this.day,
    this.once,
  });

  final String id;
  final String name;
  final CustomDateKind kind;
  final int? month;
  final int? day;
  final DateTime? once;

  bool get isAnnual => once == null && month != null && day != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    if (month != null) 'month': month,
    if (day != null) 'day': day,
    if (once != null) 'once': dateKey(once!),
  };

  static CustomHighRiskDate? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id'];
    final name = map['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    final kindName = map['kind'] is String ? map['kind'] as String : 'other';
    final kind = CustomDateKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => CustomDateKind.other,
    );
    final onceRaw = map['once'];
    DateTime? once;
    if (onceRaw is String) {
      try {
        once = parseDateOnly(onceRaw);
      } catch (_) {
        once = null;
      }
    }
    final month = map['month'] is int ? map['month'] as int : null;
    final day = map['day'] is int ? map['day'] as int : null;
    if (once == null &&
        (month == null ||
            day == null ||
            month < 1 ||
            month > 12 ||
            day < 1 ||
            day > 31)) {
      return null;
    }
    return CustomHighRiskDate(
      id: id,
      name: name.trim(),
      kind: kind,
      month: once == null ? month : null,
      day: once == null ? day : null,
      once: once,
    );
  }
}

/// One occurrence the user may want to plan for.
class UpcomingHighRisk {
  const UpcomingHighRisk({
    required this.key,
    required this.title,
    required this.date,
    required this.kind,
    required this.daysUntil,
    this.subtitle,
    this.planNote,
    this.sourceId,
  });

  /// Stable id for this occurrence, used for plans and notification payloads.
  final String key;
  final String title;
  final DateTime date;
  final HighRiskKind kind;
  final int daysUntil;
  final String? subtitle;
  final String? planNote;
  final String? sourceId;

  bool get hasPlan => planNote != null && planNote!.trim().isNotEmpty;
}

/// A scheduled 3-day-ahead plan nudge.
class HighRiskNudge {
  const HighRiskNudge({
    required this.id,
    required this.fireAt,
    required this.key,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime fireAt;
  final String key;
  final String title;
  final String body;
}

const highRiskLeadDays = 3;
const highRiskNudgeHour = 10;
const highRiskNudgeMinute = 30;

/// Notification ids 760–775. Leaves 700–740 and 800 to other features.
const highRiskDateIdStart = 760;
const highRiskDateIdEnd = 775;
const highRiskPayloadPrefix = 'high_risk:';
const highRiskPlanAction = 'action_high_risk_plan:';

/// Relapses + cravings needed before a worst weekday is shown.
const worstWeekdayMinEvents = 5;

/// The leading weekday must appear at least this often, and strictly more
/// than the runner-up, so a tie is not treated as a signal.
const worstWeekdayMinInTop = 3;

const weekdayNames = <int, String>{
  DateTime.monday: 'Monday',
  DateTime.tuesday: 'Tuesday',
  DateTime.wednesday: 'Wednesday',
  DateTime.thursday: 'Thursday',
  DateTime.friday: 'Friday',
  DateTime.saturday: 'Saturday',
  DateTime.sunday: 'Sunday',
};

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime parseDateOnly(String raw) {
  final parts = raw.split('-');
  if (parts.length != 3) {
    throw FormatException('Not a date: $raw');
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String dateKey(DateTime value) {
  final d = dateOnly(value);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

int daysBetween(DateTime from, DateTime to) =>
    dateOnly(to).difference(dateOnly(from)).inDays;

/// Payday (or any monthly day) clamped to the last day of a short month.
DateTime monthlyOn(int year, int month, int day) {
  final last = DateTime(year, month + 1, 0).day;
  final clamped = day.clamp(1, last);
  return DateTime(year, month, clamped);
}

DateTime annualOn(int year, int month, int day) => monthlyOn(year, month, day);

/// Words that must never appear in a high-risk-date notification, including
/// when private notifications are off. Checked in tests.
const highRiskForbiddenNotificationWords = <String>[
  'lean',
  'craving',
  'relapse',
  'urge',
  'slip',
  'bhang',
  'cannabis',
  'alcohol',
  'drug',
  'substance',
  'drunk',
  'high',
  'used',
  'using',
];

NotificationText highRiskNudgeCopy({
  required String name,
  required int daysUntil,
  required bool hideSensitive,
}) {
  if (hideSensitive) return neutralNotificationText;
  final when = switch (daysUntil) {
    <= 0 => 'is today',
    1 => 'is tomorrow',
    _ => 'is in $daysUntil days',
  };
  return NotificationText(
    title: 'Coming up',
    body: '$name $when. A short plan can help you get through it.',
  );
}

bool notificationCopyIsClean(NotificationText text) {
  final haystack = '${text.title} ${text.body}'.toLowerCase();
  for (final word in highRiskForbiddenNotificationWords) {
    if (RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(haystack)) {
      return false;
    }
  }
  return true;
}

/// True when [events] show a clear worst local weekday.
int? detectWorstWeekday(
  Iterable<RecoveryEvent> events, {
  required DateTime now,
  Duration lookback = const Duration(days: 180),
}) {
  bool usable(RecoveryEvent event) =>
      event.type == RecoveryEventType.relapse ||
      event.type == RecoveryEventType.craving;

  final cutoff = now.subtract(lookback);
  var scoped = events.where(usable).where((e) => !e.timestamp.isAfter(now));
  final recent = scoped.where((e) => !e.timestamp.isBefore(cutoff)).toList();
  final pool = recent.length >= worstWeekdayMinEvents
      ? recent
      : scoped.toList();
  if (pool.length < worstWeekdayMinEvents) return null;

  final counts = <int, int>{};
  for (final event in pool) {
    final local = event.timestamp.toLocal();
    counts[local.weekday] = (counts[local.weekday] ?? 0) + 1;
  }
  final ranked = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = ranked.first;
  final second = ranked.length > 1 ? ranked[1].value : 0;
  if (top.value < worstWeekdayMinInTop || top.value <= second) return null;
  return top.key;
}

List<UpcomingHighRisk> upcomingHighRiskDates({
  required DateTime now,
  required Set<String> disabledBundledIds,
  required List<CustomHighRiskDate> customDates,
  int? paydayDay,
  int? worstWeekday,
  Map<String, String> plans = const {},
  int horizonDays = 400,
  int limit = 8,
}) {
  final today = dateOnly(now);
  final horizon = today.add(Duration(days: horizonDays));
  final found = <UpcomingHighRisk>[];

  void add({
    required String key,
    required String title,
    required DateTime date,
    required HighRiskKind kind,
    String? subtitle,
    String? sourceId,
  }) {
    final day = dateOnly(date);
    if (day.isBefore(today) || day.isAfter(horizon)) return;
    found.add(
      UpcomingHighRisk(
        key: key,
        title: title,
        date: day,
        kind: kind,
        daysUntil: daysBetween(today, day),
        subtitle: subtitle,
        planNote: plans[key],
        sourceId: sourceId,
      ),
    );
  }

  for (final festival in bundledFestivals) {
    if (disabledBundledIds.contains(festival.id)) continue;
    for (final start in festival.parsedDates) {
      // A multi-day festival that has already started still counts as today
      // until its last day, so the Home card does not disappear mid-festival.
      final last = start.add(Duration(days: festival.spanDays - 1));
      DateTime shown = start;
      if (today.isAfter(start) && !today.isAfter(last)) {
        shown = today;
      }
      add(
        key: 'bundled:${festival.id}:${dateKey(start)}',
        title: festival.name,
        date: shown,
        kind: HighRiskKind.bundled,
        subtitle: festival.blurb,
        sourceId: festival.id,
      );
    }
  }

  for (final custom in customDates) {
    if (custom.once != null) {
      add(
        key: 'custom:${custom.id}:${dateKey(custom.once!)}',
        title: custom.name,
        date: custom.once!,
        kind: HighRiskKind.custom,
        subtitle: custom.kind.label,
        sourceId: custom.id,
      );
      continue;
    }
    // This year and next, so a date that just passed still has a next one.
    for (final year in [today.year, today.year + 1]) {
      final date = annualOn(year, custom.month!, custom.day!);
      add(
        key: 'custom:${custom.id}:${dateKey(date)}',
        title: custom.name,
        date: date,
        kind: HighRiskKind.custom,
        subtitle: custom.kind.label,
        sourceId: custom.id,
      );
    }
  }

  if (paydayDay != null && paydayDay >= 1 && paydayDay <= 31) {
    var cursor = DateTime(today.year, today.month, 1);
    final lastMonth = DateTime(horizon.year, horizon.month, 1);
    while (!cursor.isAfter(lastMonth)) {
      final date = monthlyOn(cursor.year, cursor.month, paydayDay);
      add(
        key: 'payday:${dateKey(date)}',
        title: 'Payday',
        date: date,
        kind: HighRiskKind.payday,
        subtitle: 'Day $paydayDay each month',
        sourceId: 'payday',
      );
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
  }

  if (worstWeekday != null &&
      worstWeekday >= DateTime.monday &&
      worstWeekday <= DateTime.sunday) {
    var cursor = today;
    while (cursor.weekday != worstWeekday) {
      cursor = cursor.add(const Duration(days: 1));
    }
    add(
      key: 'weekday:$worstWeekday:${dateKey(cursor)}',
      title: weekdayNames[worstWeekday]!,
      date: cursor,
      kind: HighRiskKind.weekday,
      subtitle: 'A harder day in your logs',
      sourceId: 'weekday',
    );
  }

  found.sort((a, b) {
    final byDay = a.daysUntil.compareTo(b.daysUntil);
    if (byDay != 0) return byDay;
    return a.title.compareTo(b.title);
  });

  // One occurrence per source (next payday, next Diwali, …).
  final seen = <String>{};
  final unique = <UpcomingHighRisk>[];
  for (final item in found) {
    final id = item.sourceId ?? item.key;
    if (!seen.add(id)) continue;
    unique.add(item);
    if (unique.length >= limit) break;
  }
  return unique;
}

/// Moves [at] to one minute after quiet hours when it would otherwise land
/// inside them. Quiet-hours-off leaves the time unchanged.
DateTime deferPastQuietHours(DateTime at, NotificationPrefs prefs) {
  if (!prefs.inQuietHours(at)) return at;
  final fireMinute = (prefs.quietHours.endMinutes + 1) % (24 * 60);
  var candidate = DateTime(
    at.year,
    at.month,
    at.day,
  ).add(Duration(minutes: fireMinute));
  if (!candidate.isAfter(at)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  var guard = 0;
  while (prefs.inQuietHours(candidate) && guard < 2) {
    candidate = candidate.add(const Duration(days: 1));
    guard++;
  }
  return candidate;
}

List<HighRiskNudge> planHighRiskNudges({
  required List<UpcomingHighRisk> upcoming,
  required NotificationPrefs prefs,
  required DateTime now,
  required bool remindersEnabled,
  int maxCount = 16,
}) {
  if (!remindersEnabled) return const [];
  final nudges = <HighRiskNudge>[];
  var slot = 0;
  for (final item in upcoming) {
    if (item.hasPlan) continue;
    if (item.kind == HighRiskKind.weekday && item.daysUntil > 7) continue;
    final occurrence = item.date;
    final ideal = DateTime(
      occurrence.year,
      occurrence.month,
      occurrence.day,
    ).subtract(const Duration(days: highRiskLeadDays));
    var fireAt = DateTime(
      ideal.year,
      ideal.month,
      ideal.day,
      highRiskNudgeHour,
      highRiskNudgeMinute,
    );
    if (fireAt.isBefore(now) || fireAt.isAtSameMomentAs(now)) {
      // Already inside the 3-day window (or the lead day is today after
      // 10:30): still nudge once, a minute from now, if there is no plan.
      if (item.daysUntil > highRiskLeadDays) continue;
      fireAt = now.add(const Duration(minutes: 1));
    }
    fireAt = deferPastQuietHours(fireAt, prefs);
    if (!fireAt.isAfter(now)) continue;
    if (!prefs.allows(NotificationKind.highRiskDate, fireAt)) continue;
    final daysAtFire = daysBetween(fireAt, occurrence);
    final copy = highRiskNudgeCopy(
      name: item.title,
      daysUntil: daysAtFire < 0 ? 0 : daysAtFire,
      hideSensitive: prefs.hideSensitive,
    );
    if (slot >= maxCount) break;
    if (highRiskDateIdStart + slot > highRiskDateIdEnd) break;
    nudges.add(
      HighRiskNudge(
        id: highRiskDateIdStart + slot,
        fireAt: fireAt,
        key: item.key,
        title: copy.title,
        body: copy.body,
      ),
    );
    slot++;
  }
  return nudges;
}

List<CustomHighRiskDate> decodeCustomHighRiskDates(Object? raw) {
  if (raw is! List) return const [];
  final out = <CustomHighRiskDate>[];
  final ids = <String>{};
  for (final item in raw) {
    final parsed = CustomHighRiskDate.tryParse(item);
    if (parsed == null || !ids.add(parsed.id)) continue;
    out.add(parsed);
    if (out.length >= 50) break;
  }
  return out;
}

Set<String> decodeIdSet(Object? raw) {
  if (raw is! List) return <String>{};
  return raw.whereType<String>().where((id) => id.isNotEmpty).toSet();
}

Map<String, String> decodePlans(Object? raw) {
  if (raw is! Map) return <String, String>{};
  final out = <String, String>{};
  raw.forEach((key, value) {
    if (key is String &&
        key.isNotEmpty &&
        value is String &&
        value.trim().isNotEmpty) {
      final trimmed = value.trim();
      if (trimmed.length <= 400) out[key] = trimmed;
    }
  });
  return out;
}

int? decodePaydayDay(Object? raw) {
  int? value;
  if (raw is int) {
    value = raw;
  } else if (raw is num && raw == raw.roundToDouble()) {
    value = raw.round();
  }
  if (value != null && value >= 1 && value <= 31) return value;
  return null;
}
