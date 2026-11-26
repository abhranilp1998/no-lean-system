import 'dart:math' as math;

import '../../recovery/domain/event_derived_state.dart';
import '../../recovery/domain/recovery_event.dart';

/// A 3-hour band of the day, e.g. 9 PM to 12 AM.
class TimeBand {
  const TimeBand(this.startHour);

  /// 0, 3, 6 ... 21.
  final int startHour;

  int get endHour => (startHour + 3) % 24;

  static TimeBand of(DateTime at) => TimeBand(at.toLocal().hour ~/ 3 * 3);

  String get label {
    String h(int hour) {
      final h12 = hour % 12 == 0 ? 12 : hour % 12;
      return '$h12 ${hour < 12 ? 'AM' : 'PM'}';
    }

    final start = h(startHour);
    final end = h(endHour);
    final sameSuffix = start.split(' ').last == end.split(' ').last;
    return sameSuffix ? '${start.split(' ').first}–$end' : '$start–$end';
  }

  @override
  bool operator ==(Object other) =>
      other is TimeBand && other.startHour == startHour;

  @override
  int get hashCode => startHour.hashCode;
}

/// What the past week looked like, from the user's own logs only.
///
/// The window is the 7 local calendar days ending today. Lean/codeine slips
/// reset the clean timer; benzo-only use is kept apart and never does.
class WeeklyRecap {
  const WeeklyRecap({
    required this.periodStart,
    required this.periodEnd,
    required this.daysCovered,
    required this.cleanDays,
    required this.streakDays,
    required this.cravings,
    required this.averageIntensity,
    required this.peakIntensity,
    required this.peakBand,
    required this.peakBandCount,
    required this.cravingsRiddenOut,
    required this.sosCompleted,
    required this.codeCompleted,
    required this.slips,
    required this.slipDays,
    required this.benzoOnlyEntries,
    required this.moneyKept,
    required this.headline,
    required this.lines,
    required this.nextStep,
  });

  final DateTime periodStart;
  final DateTime periodEnd;

  /// Days in the window since tracking began (1–7).
  final int daysCovered;
  final int cleanDays;
  final int streakDays;
  final int cravings;
  final double averageIntensity;
  final int peakIntensity;
  final TimeBand? peakBand;
  final int peakBandCount;

  /// Rechecked cravings that passed or eased, plus finished SOS and Code
  /// Instead sessions.
  final int cravingsRiddenOut;
  final int sosCompleted;
  final int codeCompleted;

  /// Lean/codeine-type slips (anything that resets the lean timer).
  final int slips;
  final int slipDays;

  /// Benzo-only entries: logged separately, never reset the lean timer.
  final int benzoOnlyEntries;

  /// Estimated money kept this week; null when no daily spend is set.
  final double? moneyKept;

  final String headline;
  final List<String> lines;
  final String nextStep;

  bool get hasAnyActivity =>
      cravings > 0 ||
      slips > 0 ||
      benzoOnlyEntries > 0 ||
      cravingsRiddenOut > 0;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// Builds the recap for the 7 days ending on [now]'s local day.
///
/// [dailySpend] is the user's existing typical daily spend; pass 0 when
/// unset and no money line is shown. [formatMoney] formats the amount so
/// the caller can use the user's currency.
WeeklyRecap computeWeeklyRecap({
  required Iterable<RecoveryEvent> events,
  required DateTime lastDose,
  required DateTime now,
  double dailySpend = 0,
  String Function(num)? formatMoney,
}) {
  final localNow = now.toLocal();
  final today = _day(localNow);
  final windowStart = today.subtract(const Duration(days: 6));
  final windowEnd = today.add(const Duration(days: 1));

  bool inWindow(DateTime t) {
    final l = t.toLocal();
    return !l.isBefore(windowStart) && l.isBefore(windowEnd);
  }

  final all = events.toList();
  // Tracking began with the earliest baseline, or the earliest event.
  final baselines =
      all
          .where((e) => e.type == RecoveryEventType.recoveryStart)
          .map((e) => e.timestamp.toLocal())
          .toList()
        ..sort();
  final trackingStart = baselines.isNotEmpty
      ? _day(baselines.first)
      : (all.isEmpty
            ? today
            : _day(
                all
                    .map((e) => e.timestamp.toLocal())
                    .reduce((a, b) => a.isBefore(b) ? a : b),
              ));

  final slipEvents = <RecoveryEvent>[];
  var benzoOnly = 0;
  final cravingEvents = <RecoveryEvent>[];
  var recheckedOk = 0;
  var sosDone = 0;
  var codeDone = 0;
  for (final e in all) {
    if (!inWindow(e.timestamp)) continue;
    switch (e.type) {
      case RecoveryEventType.relapse:
        if (resetsLeanCleanTimer(e)) {
          slipEvents.add(e);
        } else {
          benzoOnly++;
        }
      case RecoveryEventType.craving:
        cravingEvents.add(e);
      case RecoveryEventType.cravingCheck:
        final outcome = e.metadata['outcome'];
        if (outcome == 'gone' || outcome == 'eased') recheckedOk++;
      case RecoveryEventType.sosComplete:
        sosDone++;
      case RecoveryEventType.codeSession:
        if (e.metadata['completed'] == true) codeDone++;
      default:
        break;
    }
  }

  // Days that count: from the later of window start and tracking start.
  final firstDay = trackingStart.isAfter(windowStart)
      ? trackingStart
      : windowStart;
  final daysCovered = math.max(1, today.difference(firstDay).inDays + 1);
  final slipDayKeys = {for (final e in slipEvents) _day(e.timestamp.toLocal())};
  var cleanDayCount = 0;
  var cleanUnits = 0.0;
  for (var i = 0; i < daysCovered; i++) {
    final d = firstDay.add(Duration(days: i));
    if (slipDayKeys.contains(d)) continue;
    cleanDayCount++;
    // Today only counts for the part that has passed.
    cleanUnits += d == today
        ? (localNow.hour * 60 + localNow.minute) / (24 * 60)
        : 1.0;
  }

  final intensities = [
    for (final e in cravingEvents)
      ((e.metadata['intensity'] as num?)?.round() ?? 5).clamp(0, 10),
  ];
  final avg = intensities.isEmpty
      ? 0.0
      : intensities.reduce((a, b) => a + b) / intensities.length;
  final peakIntensity = intensities.isEmpty
      ? 0
      : intensities.reduce((a, b) => a > b ? a : b);

  final bandCounts = <TimeBand, int>{};
  for (final e in cravingEvents) {
    bandCounts.update(
      TimeBand.of(e.timestamp),
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  // A "peak" needs a repeat; one craving is not a pattern. Ties go to the
  // later band, where evening urges usually sit.
  final ranked = bandCounts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0
          ? byCount
          : b.key.startHour.compareTo(a.key.startHour);
    });
  final TimeBand? peak = ranked.isNotEmpty && ranked.first.value >= 2
      ? ranked.first.key
      : null;
  final peakCount = peak == null ? 0 : ranked.first.value;

  final ridden = recheckedOk + sosDone + codeDone;
  final streak = math.max(0, localNow.difference(lastDose.toLocal()).inDays);
  final money = dailySpend > 0 ? dailySpend * cleanUnits : null;
  final fmt = formatMoney ?? (num v) => v.round().toString();

  final headline = _headline(
    daysCovered: daysCovered,
    cleanDays: cleanDayCount,
    slips: slipEvents.length,
    cravings: cravingEvents.length,
  );

  final lines = <String>[
    '${cleanDayCount == daysCovered ? 'All $daysCovered' : '$cleanDayCount of $daysCovered'}'
        ' ${daysCovered == 1 ? 'day' : 'days'} clean'
        '${streak > 0 ? ', and your current streak is ${_plural(streak, 'day')}' : ''}.',
    if (cravingEvents.isEmpty)
      'No cravings logged this week. A quiet stretch is worth noticing.'
    else
      'You logged ${_plural(cravingEvents.length, 'craving')}'
          ' (average ${avg.toStringAsFixed(1)}/10, strongest $peakIntensity/10)'
          '${peak != null ? ', most often around ${peak.label}' : ''}.',
    if (ridden > 0)
      'You rode out ${_plural(ridden, 'urge')}'
          '${_riddenBreakdown(recheckedOk, sosDone, codeDone)}.',
    if (slipEvents.isNotEmpty)
      '${_plural(slipEvents.length, 'slip')} on ${_plural(slipDayKeys.length, 'day')}.'
          ' That is information, not a verdict: you are still here and still counting.',
    if (benzoOnly > 0)
      '${_plural(benzoOnly, 'benzo entry', 'benzo entries')} logged separately.'
          ' It does not reset your lean timer, and it still matters for safety.',
    if (money != null && money >= 1) 'About ${fmt(money)} kept this week.',
  ];

  final next = _nextStep(
    slips: slipEvents.length,
    benzoOnly: benzoOnly,
    peak: peak,
    cravings: cravingEvents.length,
    cleanDays: cleanDayCount,
    daysCovered: daysCovered,
    ridden: ridden,
  );

  return WeeklyRecap(
    periodStart: windowStart,
    periodEnd: localNow,
    daysCovered: daysCovered,
    cleanDays: cleanDayCount,
    streakDays: streak,
    cravings: cravingEvents.length,
    averageIntensity: avg,
    peakIntensity: peakIntensity,
    peakBand: peak,
    peakBandCount: peakCount,
    cravingsRiddenOut: ridden,
    sosCompleted: sosDone,
    codeCompleted: codeDone,
    slips: slipEvents.length,
    slipDays: slipDayKeys.length,
    benzoOnlyEntries: benzoOnly,
    moneyKept: money != null && money >= 1 ? money : null,
    headline: headline,
    lines: lines,
    nextStep: next,
  );
}

String _riddenBreakdown(int rechecked, int sos, int code) {
  final parts = <String>[
    if (rechecked > 0) '$rechecked passed or eased on a recheck',
    if (sos > 0) '$sos through SOS',
    if (code > 0) '$code with Code Instead',
  ];
  return parts.isEmpty ? '' : ' (${parts.join(', ')})';
}

String _headline({
  required int daysCovered,
  required int cleanDays,
  required int slips,
  required int cravings,
}) {
  if (slips == 0 && cleanDays == daysCovered) {
    return daysCovered >= 7
        ? 'A clean week. That is real.'
        : 'Clean so far, and it counts.';
  }
  if (slips > 0 && cleanDays >= daysCovered / 2) {
    return 'Mostly clean, with a rough patch. Still moving.';
  }
  if (slips > 0) {
    return 'A hard week, and you are still here.';
  }
  return 'Another week in the books.';
}

String _nextStep({
  required int slips,
  required int benzoOnly,
  required TimeBand? peak,
  required int cravings,
  required int cleanDays,
  required int daysCovered,
  required int ridden,
}) {
  if (benzoOnly >= 3) {
    return 'You logged benzos several times. Stopping benzos suddenly can be '
        'risky, so mention it to your doctor or your SOS contact this week '
        'before changing anything.';
  }
  if (slips > 0) {
    return peak != null
        ? 'Pick one thing that would have helped before ${peak.label}, and set '
              'it up tonight: a call, a walk, or a Code Instead task.'
        : 'Pick one thing that would have helped before the slip, and set it up '
              'tonight: a call, a walk, or a Code Instead task.';
  }
  if (peak != null) {
    return 'Your cravings cluster around ${peak.label}. Plan one thing for that '
        'window tomorrow: a walk, a call, or a Code Instead task.';
  }
  if (cravings == 0 && cleanDays == daysCovered) {
    return 'Quiet week. Keep marking each day clean, and write down one reason '
        'you are glad you stayed.';
  }
  if (ridden > 0) {
    return 'What got you through this week? Do that again the next time an urge '
        'shows up.';
  }
  return 'Keep going: one clean day at a time is the whole plan.';
}
