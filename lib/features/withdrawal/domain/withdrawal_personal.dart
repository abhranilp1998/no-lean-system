/// Personalises the withdrawal guide from the user's own logs.
library;

import 'dart:math' as math;

import '../../progress/domain/dose_insights.dart';
import '../../recovery/domain/recovery_event.dart';
import '../../recovery/domain/relapse_log_entry.dart';
import '../../recovery/domain/risk_window.dart';
import 'withdrawal_guide.dart';

enum DoseLevel { unknown, low, moderate, high }

/// Hours for the user's acute course, shifted by dose level.
class Course {
  const Course(this.onsetH, this.peakStartH, this.peakEndH, this.acuteEndH);
  final int onsetH;
  final int peakStartH;
  final int peakEndH;
  final int acuteEndH;
  static const pawsEndH = 24 * 120;
}

Course courseFor(DoseLevel level) => switch (level) {
  DoseLevel.low => const Course(8, 24, 60, 24 * 5),
  DoseLevel.moderate || DoseLevel.unknown => const Course(8, 24, 72, 24 * 7),
  DoseLevel.high => const Course(6, 24, 96, 24 * 10),
};

class DoseProfile {
  const DoseProfile({
    required this.level,
    required this.avgMlPerUseDay,
    required this.useDays,
    required this.spanDays,
    required this.loggedUses,
  });
  final DoseLevel level;
  final double? avgMlPerUseDay;
  final int useDays;
  final int spanDays;
  final int loggedUses;

  /// Typical syrups carry about 10 mg codeine per 5 ml.
  double? get approxCodeineMg =>
      avgMlPerUseDay == null ? null : avgMlPerUseDay! * 2;
}

bool _isOpioid(RelapseType? t) =>
    t == null ||
    t == RelapseType.fullLean ||
    t == RelapseType.partial ||
    t == RelapseType.leanPlusAlcohol ||
    t == RelapseType.other;

DoseProfile doseProfile(Iterable<RecoveryEvent> events, DateTime now) {
  final recs = doseRecords(events).where((r) => _isOpioid(r.type)).toList();
  final since = now.subtract(const Duration(days: 60));
  final recent = recs.where((r) => r.at.isAfter(since)).toList();
  final byDay = <DateTime, double>{};
  for (final r in recent) {
    final ml = r.dose?.amountMl;
    if (ml == null) continue;
    final l = r.at.toLocal();
    final d = DateTime(l.year, l.month, l.day);
    byDay[d] = (byDay[d] ?? 0) + ml;
  }
  final avg = byDay.isEmpty
      ? null
      : byDay.values.reduce((a, b) => a + b) / byDay.length;
  final span = recs.length < 2
      ? 0
      : recs.last.at.difference(recs.first.at).inDays;
  var level = DoseLevel.unknown;
  if (avg != null) {
    level = avg < 60
        ? DoseLevel.low
        : avg < 200
        ? DoseLevel.moderate
        : DoseLevel.high;
  }
  // Long logged history nudges severity up one step.
  if (span >= 180 && level == DoseLevel.low) level = DoseLevel.moderate;
  if (span >= 365 && level == DoseLevel.moderate) level = DoseLevel.high;
  return DoseProfile(
    level: level,
    avgMlPerUseDay: avg,
    useDays: byDay.length,
    spanDays: span,
    loggedUses: recs.length,
  );
}

/// Most common craving hour (local), from at least 3 cravings.
int? cravingPeakHour(Iterable<RecoveryEvent> events) {
  final counts = <int, int>{};
  for (final e in events) {
    if (e.type == RecoveryEventType.craving ||
        e.type == RecoveryEventType.relapse) {
      final h = e.timestamp.toLocal().hour;
      counts[h] = (counts[h] ?? 0) + 1;
    }
  }
  if (counts.values.fold(0, (a, b) => a + b) < 3) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

String hourLabel(int h) {
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12 ${h < 12 ? 'AM' : 'PM'}';
}

enum Trend { none, better, same, worse }

int checkInScore(SymptomCheckIn c) => c.severities.entries
    .where((e) => !e.key.isRedFlag)
    .fold(0, (a, e) => a + e.value);

Trend checkInTrend(List<SymptomCheckIn> newestFirst) {
  if (newestFirst.length < 2) return Trend.none;
  final a = checkInScore(newestFirst[0]);
  final b = checkInScore(newestFirst[1]);
  if (a < b - 1) return Trend.better;
  if (a > b + 1) return Trend.worse;
  return Trend.same;
}

class ForecastLine {
  const ForecastLine(this.label, this.text);
  final String label;
  final String text;
}

class PersonalPlan {
  PersonalPlan({
    required this.anchor,
    required this.anchorSource,
    required this.sinceLastUse,
    required this.dose,
    required this.course,
    required this.stage,
    required this.forecast,
    required this.reasons,
    required this.trendText,
    required this.riskTonight,
    required this.inRelapse,
    required this.noData,
  });
  final DateTime anchor;
  final String anchorSource;
  final Duration sinceLastUse;
  final DoseProfile dose;
  final Course course;
  final WithdrawalStage stage;
  final List<ForecastLine> forecast;
  final List<String> reasons;
  final String? trendText;
  final String? riskTonight;
  final bool inRelapse;
  final bool noData;

  /// 0..1 position on the acute timeline (0 to acute end).
  double get acuteProgress =>
      (sinceLastUse.inMinutes / (course.acuteEndH * 60)).clamp(0.0, 1.0);
}

String _range(int h) =>
    h < 48 ? '$h h' : 'day ${(h / 24).toStringAsFixed(h % 24 == 0 ? 0 : 1)}';

String _phaseAt(int h, Course c) {
  if (h < c.onsetH) return 'mostly early signs (restless, yawning, runny nose)';
  if (h < c.peakStartH) return 'aches, sweats, poor sleep building';
  if (h < c.peakEndH) return 'peak: cramps, loose stools, chills, cravings';
  if (h < c.acuteEndH) return 'easing: body calming, tired, sleep still off';
  return 'past the physical part: mood and sleep slowly recovering';
}

PersonalPlan buildPlan({
  required Iterable<RecoveryEvent> events,
  required DateTime cleanSince,
  required DateTime now,
  required RiskWindow riskWindow,
  List<SymptomCheckIn> checkIns = const [],
}) {
  final relapses =
      events.where((e) => e.type == RecoveryEventType.relapse).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final lastRelapse = relapses.lastOrNull?.timestamp;
  var anchor = cleanSince;
  var source = 'your clean timer';
  if (lastRelapse != null && lastRelapse.isAfter(cleanSince)) {
    anchor = lastRelapse;
    source = 'your last logged use';
  } else if (lastRelapse != null &&
      lastRelapse.difference(cleanSince).abs() < const Duration(minutes: 5)) {
    source = 'your last logged use';
  }
  var since = now.difference(anchor);
  if (since.isNegative) since = Duration.zero;
  final dose = doseProfile(events, now);
  final course = courseFor(dose.level);
  final h = since.inHours;
  final stage = stageFor(since);
  final reasons = <String>['Time counted from $source (${_range(h)} ago).'];
  if (dose.avgMlPerUseDay != null) {
    reasons.add(
      'Logged use averages about ${dose.avgMlPerUseDay!.round()} ml on days you used '
      '(~${dose.approxCodeineMg!.round()} mg codeine at 10 mg/5 ml) over ${dose.useDays} day(s): '
      '${switch (dose.level) {
        DoseLevel.low => 'a lower dose, so a shorter, milder course is likely',
        DoseLevel.high => 'a high dose, so expect a longer, stronger course',
        _ => 'a moderate dose, typical course',
      }}.',
    );
  }
  if (dose.spanDays >= 30) {
    reasons.add(
      'Your logs span ${dose.spanDays} days; longer use can stretch things out.',
    );
  }
  final recentRelapses = relapses
      .where((e) => now.difference(e.timestamp) < const Duration(days: 14))
      .length;
  final inRelapse = h < 12 && lastRelapse != null && anchor == lastRelapse;
  if (recentRelapses >= 2) {
    reasons.add(
      '$recentRelapses uses logged in the last 2 weeks. Stop-start keeps restarting the clock; a doctor-guided taper can make it easier.',
    );
  }

  final peak = cravingPeakHour(events);
  String? risk;
  final local = now.toLocal();
  final peakText = peak != null ? hourLabel(peak) : null;
  final windowStart = RiskWindow.formatMinutes(riskWindow.startMinutes);
  if (peak != null && local.hour <= peak) {
    risk =
        'Your cravings and slips cluster around $peakText. Tonight around then is a risk: plan something for $peakText.';
    reasons.add('Craving/use logs peak around $peakText.');
  } else if (riskWindow.contains(local)) {
    risk =
        'You are inside your risk window now. Ride out the next wave; it passes.';
  } else if (local.hour * 60 < riskWindow.startMinutes) {
    risk = 'Your risk window starts at $windowStart. Have a plan ready.';
  }

  String forecastAt(int addH) => _phaseAt(h + addH, course);
  final hoursToMidnight = 24 - local.hour;
  final endH = course.acuteEndH;
  final forecast = <ForecastLine>[
    ForecastLine('Next 6 hours', forecastAt(6)),
    ForecastLine('Tonight', forecastAt(math.max(1, 22 - local.hour))),
    ForecastLine('Tomorrow', forecastAt(hoursToMidnight + 12)),
    ForecastLine(
      'When it ends',
      h >= endH
          ? 'The physical part is behind you. Mood, sleep and cravings keep improving over weeks to months (PAWS).'
          : 'Physical symptoms likely ease by around day ${(endH / 24).round()} '
                '(about ${endH - h} more hours). Worst usually lifts after ${_range(course.peakEndH)}. '
                'Sleep and mood can take weeks.',
    ),
  ];

  String? trendText;
  final trend = checkInTrend(checkIns);
  final expectWorse = h < course.peakEndH;
  if (trend != Trend.none) {
    trendText = switch (trend) {
      Trend.better =>
        'Your check-ins are improving. ${expectWorse ? 'Earlier than usual. Nice.' : 'Right on track.'}',
      Trend.same =>
        'Symptoms about the same as last check-in. ${expectWorse ? 'Normal for the peak.' : 'Should start easing soon.'}',
      Trend.worse =>
        expectWorse
            ? 'Symptoms rising since last check-in. Expected during the peak, but watch fluids.'
            : 'Symptoms rising after the peak, which is unusual. Worth calling a doctor.',
      Trend.none => null,
    };
  }

  return PersonalPlan(
    anchor: anchor,
    anchorSource: source,
    sinceLastUse: since,
    dose: dose,
    course: course,
    stage: stage,
    forecast: forecast,
    reasons: reasons,
    trendText: trendText,
    riskTonight: risk,
    inRelapse: inRelapse,
    noData: relapses.isEmpty && peak == null,
  );
}
