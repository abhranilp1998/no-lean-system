import 'notification_policy.dart';
import 'recovery_event.dart';
import 'risk_window.dart';

/// A heads-up about 30 minutes before the user's own craving/slip peak.
///
/// This is fully offline and derived only from logged events. The occurred
/// time is [RecoveryEvent.timestamp] (relapses logged later still store the
/// real time there; `recordedAt` in metadata is when it was written down).
///
/// Hook after PR #33 (private notification wording) merges: add
/// [cravingPeakChannel] to `NotificationChannels` and a
/// `cravingPeakSurface()` built from [cravingPeakCopy] to
/// `everyFlutterNotificationSurface`. Until then, [NotificationService]
/// already runs title, body, ticker and action labels through
/// [NotificationPrefs.textFor] / [NotificationPrefs.label].
const cravingPeakLead = Duration(minutes: 30);

/// Enough personal history to trust a peak: 5 cravings or slips on at least
/// 3 different local days, with a clear top hour.
const minPeakSignals = 5;
const minPeakDays = 3;
const minPeakHourCount = 3;

/// Prefer the last 60 days when that window still has enough data.
const peakLookback = Duration(days: 60);

/// Notification IDs 520 (daily) or 520 + weekday (1–7) for weekday-only peaks.
const cravingPeakFirstId = 520;
const cravingPeakLastId = 527;

/// Channel metadata so PR #33 can drop this into its catalogue without
/// inventing new wording. The id must stay `craving_peak_v1`.
const cravingPeakChannel = (
  id: 'craving_peak_v1',
  publicName: 'NO LEAN usual peak',
  publicDescription:
      'A heads-up about 30 minutes before your usual craving peak',
  privateName: 'Daily check-in',
  privateDescription: 'A heads-up before a usual time of day',
);

/// When a craving or slip actually happened, in local time.
DateTime occurredAtOf(RecoveryEvent event) => event.timestamp.toLocal();

class CravingPeakPlan {
  const CravingPeakPlan({
    required this.peakHour,
    required this.headsUpMinutes,
    required this.count,
    required this.total,
    required this.weekdays,
  });

  /// Hour of day (0–23) when cravings and slips cluster.
  final int peakHour;

  /// Minute-of-day the notification should fire (30 minutes before [peakHour]).
  final int headsUpMinutes;

  /// How many of the considered signals landed in [peakHour].
  final int count;
  final int total;

  /// Empty means every day. Otherwise 1 = Monday … 7 = Sunday (Dart weekdays).
  final List<int> weekdays;

  bool get isDaily => weekdays.isEmpty;

  String get peakLabel => formatPeakHour(peakHour);

  NotificationText get copy =>
      cravingPeakCopy(peakHour: peakHour, weekdays: weekdays);
}

enum CravingPeakSkip { needsData, overlapsRiskWindow }

class CravingPeakInsight {
  const CravingPeakInsight.ready(this.plan) : skip = null;
  const CravingPeakInsight.skip(this.skip) : plan = null;

  final CravingPeakPlan? plan;
  final CravingPeakSkip? skip;
}

/// Builds the user's current heads-up, or `null` when there is not enough
/// data, no clear peak, or the peak already sits in the risk window.
CravingPeakPlan? buildCravingPeakPlan({
  required List<RecoveryEvent> events,
  required RiskWindow riskWindow,
  DateTime? now,
}) => analyzeCravingPeak(events: events, riskWindow: riskWindow, now: now).plan;

CravingPeakInsight analyzeCravingPeak({
  required List<RecoveryEvent> events,
  required RiskWindow riskWindow,
  DateTime? now,
}) {
  final moment = (now ?? DateTime.now()).toLocal();
  final signals = _signals(events, moment);
  final days = <String>{
    for (final event in signals) _dateKey(occurredAtOf(event)),
  };
  if (signals.length < minPeakSignals || days.length < minPeakDays) {
    return const CravingPeakInsight.skip(CravingPeakSkip.needsData);
  }

  final hours = <int, int>{};
  for (final event in signals) {
    final hour = occurredAtOf(event).hour;
    hours[hour] = (hours[hour] ?? 0) + 1;
  }
  final ranked = hours.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  final top = ranked.first;
  final second = ranked.length > 1 ? ranked[1].value : 0;
  final clear = top.value >= minPeakHourCount && top.value > second;
  if (!clear) {
    return const CravingPeakInsight.skip(CravingPeakSkip.needsData);
  }

  final headsUp =
      (top.key * 60 - cravingPeakLead.inMinutes) % RiskWindow.minutesPerDay;
  if (_overlapsRiskWindow(riskWindow, headsUp, top.key * 60)) {
    return const CravingPeakInsight.skip(CravingPeakSkip.overlapsRiskWindow);
  }

  return CravingPeakInsight.ready(
    CravingPeakPlan(
      peakHour: top.key,
      headsUpMinutes: headsUp,
      count: top.value,
      total: signals.length,
      weekdays: _concentratedWeekdays(signals, top.key),
    ),
  );
}

/// Settings subtitle. Off, waiting on data, skipped as a duplicate of the
/// risk window, or the concrete 30-minute heads-up.
String cravingPeakSettingSubtitle({
  required bool enabled,
  required CravingPeakInsight insight,
}) {
  if (!enabled) return 'Off';
  final plan = insight.plan;
  if (plan != null) {
    return '30 min before your usual ${plan.peakLabel} peak // '
        'skipped when it is already inside the risk window';
  }
  if (insight.skip == CravingPeakSkip.overlapsRiskWindow) {
    return 'On // skipped because the usual peak is already inside the risk window';
  }
  return 'On // needs 5 cravings or slips across 3 days to start';
}

/// Sensitive wording, before [NotificationPrefs.textFor] is applied.
NotificationText cravingPeakCopy({
  required int peakHour,
  List<int> weekdays = const [],
}) {
  final when = formatPeakHour(peakHour);
  final dayBit = _weekdayPhrase(weekdays);
  final title = dayBit == null
      ? 'USUAL PEAK AROUND $when'
      : 'USUAL PEAK $dayBit AROUND $when';
  final subject = dayBit == null
      ? 'Your cravings usually hit around $when.'
      : 'Your $dayBit usually get hard around $when.';
  return NotificationText(
    title: title,
    body: '$subject Plan something now: call your person, walk, or eat.',
  );
}

String formatPeakHour(int hour) {
  final h = hour % 24;
  if (h == 0) return '12 AM';
  if (h == 12) return '12 PM';
  if (h < 12) return '$h AM';
  return '${h - 12} PM';
}

const _weekdayNames = <int, String>{
  DateTime.monday: 'Mondays',
  DateTime.tuesday: 'Tuesdays',
  DateTime.wednesday: 'Wednesdays',
  DateTime.thursday: 'Thursdays',
  DateTime.friday: 'Fridays',
  DateTime.saturday: 'Saturdays',
  DateTime.sunday: 'Sundays',
};

String? _weekdayPhrase(List<int> weekdays) {
  if (weekdays.isEmpty) return null;
  final names = [for (final d in weekdays) _weekdayNames[d]!];
  if (names.length == 1) return names.single;
  return '${names.first} and ${names.last}';
}

List<RecoveryEvent> _signals(List<RecoveryEvent> events, DateTime now) {
  final all = [
    for (final event in events)
      if (event.type == RecoveryEventType.craving ||
          event.type == RecoveryEventType.relapse)
        event,
  ];
  final recent = [
    for (final event in all)
      if (!now.difference(occurredAtOf(event)).isNegative &&
          now.difference(occurredAtOf(event)) <= peakLookback)
        event,
  ];
  return recent.length >= minPeakSignals ? recent : all;
}

String _dateKey(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}-'
    '${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';

/// Skip when the heads-up or the peak itself falls inside (or at the start
/// of) the existing risk window, so we do not double up with those alerts.
bool _overlapsRiskWindow(
  RiskWindow window,
  int headsUpMinutes,
  int peakStartMinutes,
) {
  if (peakStartMinutes == window.startMinutes) return true;
  return window.contains(_clock(headsUpMinutes)) ||
      window.contains(_clock(peakStartMinutes));
}

DateTime _clock(int minuteOfDay) {
  final normalized = minuteOfDay % RiskWindow.minutesPerDay;
  return DateTime(2026, 1, 1, normalized ~/ 60, normalized % 60);
}

/// If the peak hour is really a one- or two-weekday habit, only fire then.
/// Otherwise empty (daily).
List<int> _concentratedWeekdays(List<RecoveryEvent> signals, int peakHour) {
  final inHour = [
    for (final event in signals)
      if (occurredAtOf(event).hour == peakHour) occurredAtOf(event).weekday,
  ];
  if (inHour.length < minPeakHourCount) return const [];
  final counts = <int, int>{};
  for (final day in inHour) {
    counts[day] = (counts[day] ?? 0) + 1;
  }
  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  final top = ranked.first;
  if (top.value >= 3 && top.value / inHour.length >= 0.5) {
    if (ranked.length >= 2 &&
        ranked[1].value >= 2 &&
        (top.value + ranked[1].value) / inHour.length >= 0.7) {
      final days = [top.key, ranked[1].key]..sort();
      return List.unmodifiable(days);
    }
    return [top.key];
  }
  if (ranked.length >= 2 &&
      ranked[1].value >= 2 &&
      (top.value + ranked[1].value) / inHour.length >= 0.7) {
    final days = [top.key, ranked[1].key]..sort();
    return List.unmodifiable(days);
  }
  return const [];
}
