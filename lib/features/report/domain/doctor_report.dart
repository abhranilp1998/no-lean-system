import '../../companion/domain/companion_state.dart';
import '../../recap/domain/weekly_recap.dart' show TimeBand;
import '../../recovery/domain/dose_units.dart';
import '../../recovery/domain/event_derived_state.dart';
import '../../recovery/domain/mixing_safety_net.dart';
import '../../recovery/domain/recovery_event.dart';
import '../../recovery/domain/relapse_log_entry.dart';
import '../../withdrawal/domain/withdrawal_guide.dart';

/// Most timeline rows one report carries. Longer ranges say so on the page.
const doctorReportMaxRows = 1000;

/// An inclusive range of local calendar days.
class DoctorReportRange {
  DoctorReportRange(DateTime start, DateTime end)
    : start = DateTime(start.year, start.month, start.day),
      end = DateTime(end.year, end.month, end.day) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('The end date is before the start date.');
    }
  }

  factory DoctorReportRange.lastDays(int days, DateTime now) =>
      DoctorReportRange(now.subtract(Duration(days: days - 1)), now);

  final DateTime start;
  final DateTime end;

  DateTime get endExclusive => DateTime(end.year, end.month, end.day + 1);

  int get dayCount => endExclusive.difference(start).inDays;

  bool contains(DateTime t) {
    final l = t.toLocal();
    return !l.isBefore(start) && l.isBefore(endExclusive);
  }
}

/// What kind of substance one timeline row is. "Mixed" is a flag on a row,
/// not a kind.
enum ReportSubstance { codeine, benzo, alcohol, codeineAlcohol, other, unknown }

extension ReportSubstanceLabel on ReportSubstance {
  String get label => switch (this) {
    ReportSubstance.codeine => 'Codeine / lean',
    ReportSubstance.benzo => 'Benzodiazepine',
    ReportSubstance.alcohol => 'Alcohol',
    ReportSubstance.codeineAlcohol => 'Codeine / lean + alcohol',
    ReportSubstance.other => 'Other',
    ReportSubstance.unknown => 'Not specified',
  };
}

ReportSubstance reportSubstanceOf(RelapseType? type) => switch (type) {
  RelapseType.fullLean || RelapseType.partial => ReportSubstance.codeine,
  RelapseType.benzo => ReportSubstance.benzo,
  RelapseType.alcohol => ReportSubstance.alcohol,
  RelapseType.leanPlusAlcohol => ReportSubstance.codeineAlcohol,
  RelapseType.other => ReportSubstance.other,
  null => ReportSubstance.unknown,
};

class ReportUseEntry {
  const ReportUseEntry({
    required this.at,
    required this.substance,
    required this.amountText,
    required this.ml,
    required this.mixed,
    required this.resetsLeanTimer,
    this.note = '',
    this.stress,
  });

  final DateTime at;
  final ReportSubstance substance;

  /// What was entered, e.g. `2.5 bottles · 250 ml`, `2 tablets`, or the
  /// user's own words. Empty when nothing was recorded.
  final String amountText;

  /// Volume in ml at the time of logging; null for tablets, drinks, or
  /// entries with no amount.
  final double? ml;

  /// Taken together with another depressant in the same sitting.
  final bool mixed;
  final bool resetsLeanTimer;
  final String note;
  final int? stress;
}

class ReportSubstanceTotals {
  ReportSubstanceTotals(this.substance);
  final ReportSubstance substance;
  int entries = 0;
  final Set<DateTime> days = {};
  double totalMl = 0;
  int volumeEntries = 0;
  double maxMl = 0;
  int countEntries = 0;

  int get useDays => days.length;
  double? get avgMlPerUseDay =>
      useDays == 0 || volumeEntries == 0 ? null : totalMl / useDays;
}

class ReportCheckIn {
  const ReportCheckIn({
    required this.at,
    required this.symptoms,
    required this.redFlags,
  });

  final DateTime at;

  /// Ordinary symptoms with severity 1 (mild) to 3 (severe).
  final List<({String label, int severity})> symptoms;

  /// Labels of any red-flag symptoms ticked.
  final List<String> redFlags;
}

class ReportStreak {
  const ReportStreak({
    required this.from,
    required this.to,
    required this.days,
    required this.ongoing,
    required this.startedBeforeRange,
  });

  final DateTime from;
  final DateTime to;
  final int days;
  final bool ongoing;
  final bool startedBeforeRange;
}

class ReportCravings {
  const ReportCravings({
    required this.count,
    required this.averageIntensity,
    required this.peakIntensity,
    required this.topTriggers,
    required this.topBands,
    required this.recheckOutcomes,
    required this.sosCompleted,
    required this.codeCompleted,
  });

  final int count;
  final double averageIntensity;
  final int peakIntensity;
  final List<({String label, int count})> topTriggers;
  final List<({String label, int count})> topBands;

  /// How rechecked cravings ended: gone / eased / same / stronger.
  final Map<String, int> recheckOutcomes;
  final int sosCompleted;
  final int codeCompleted;
}

class DoctorReportData {
  const DoctorReportData({
    required this.range,
    required this.generatedAt,
    required this.entries,
    required this.entriesTotal,
    required this.totals,
    required this.mixedEntries,
    required this.checkIns,
    required this.cravings,
    required this.streaks,
    required this.longestStreakDays,
    required this.medicines,
    required this.declaredSubstances,
  });

  final DoctorReportRange range;
  final DateTime generatedAt;

  /// Timeline rows, oldest first, capped at [doctorReportMaxRows] (most
  /// recent kept).
  final List<ReportUseEntry> entries;
  final int entriesTotal;
  final List<ReportSubstanceTotals> totals;
  final int mixedEntries;
  final List<ReportCheckIn> checkIns;
  final ReportCravings cravings;
  final List<ReportStreak> streaks;
  final int longestStreakDays;
  final String medicines;
  final List<String> declaredSubstances;

  bool get truncated => entriesTotal > entries.length;
  bool get hasRedFlags => checkIns.any((c) => c.redFlags.isNotEmpty);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Builds the report from the user's own data. Nothing here touches the
/// network, and it is only called when the user asks for a report.
DoctorReportData buildDoctorReport({
  required Iterable<RecoveryEvent> events,
  required Iterable<SymptomCheckIn> checkIns,
  required DoctorReportRange range,
  required DateTime now,
  CompanionState? companion,
  String medicines = '',
}) {
  final all = events.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final relapses = [
    for (final e in all)
      if (e.type == RecoveryEventType.relapse) e,
  ];

  // Mixed: codeine with alcohol or benzos, within 6 hours, from one save.
  String saveKey(RecoveryEvent e) =>
      '${e.metadata['batchId'] ?? e.metadata['recordedAt'] ?? e.timestamp.toIso8601String()}';
  final mixedIds = <String>{};
  final bySave = <String, List<RecoveryEvent>>{};
  for (final e in relapses) {
    bySave.putIfAbsent(saveKey(e), () => []).add(e);
  }
  for (final group in bySave.values) {
    // Split a save into 6-hour sittings so a bulk catch-up is not "mixed".
    var sitting = <RecoveryEvent>[];
    void flush() {
      if (sitting.isEmpty) return;
      final types = [
        for (final e in sitting)
          RelapseTypeLabel.fromName(e.metadata['relapseType']),
      ].whereType<RelapseType>();
      if (isMixedSave(types)) mixedIds.addAll(sitting.map((e) => e.id));
      sitting = [];
    }

    group.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    for (final e in group) {
      if (sitting.isNotEmpty &&
          e.timestamp.difference(sitting.first.timestamp) >
              const Duration(hours: 6)) {
        flush();
      }
      sitting.add(e);
    }
    flush();
  }

  final inRange = relapses.where((e) => range.contains(e.timestamp)).toList();
  final rows = <ReportUseEntry>[];
  final totalsByKind = <ReportSubstance, ReportSubstanceTotals>{};
  for (final e in inRange) {
    final type = RelapseTypeLabel.fromName(e.metadata['relapseType']);
    final kind = reportSubstanceOf(type);
    final dose = DoseAmount.fromMetadata(e.metadata);
    final quantity = (e.metadata['quantity'] as String?)?.trim() ?? '';
    final ml = dose?.amountMl;
    final stress = e.metadata['stress'];
    rows.add(
      ReportUseEntry(
        at: e.timestamp.toLocal(),
        substance: kind,
        amountText: dose?.display ?? quantity,
        ml: ml,
        mixed: mixedIds.contains(e.id) || type == RelapseType.leanPlusAlcohol,
        resetsLeanTimer: resetsLeanCleanTimer(e),
        note: ((e.metadata['note'] as String?) ?? '').trim(),
        stress: stress is int ? stress : null,
      ),
    );
    final t = totalsByKind.putIfAbsent(kind, () => ReportSubstanceTotals(kind));
    t.entries++;
    t.days.add(_day(e.timestamp.toLocal()));
    if (ml != null) {
      t.totalMl += ml;
      t.volumeEntries++;
      if (ml > t.maxMl) t.maxMl = ml;
    } else if (dose != null) {
      t.countEntries++;
    }
  }
  final totalRows = rows.length;
  final shownRows = totalRows > doctorReportMaxRows
      ? rows.sublist(totalRows - doctorReportMaxRows)
      : rows;
  final totals = totalsByKind.values.toList()
    ..sort((a, b) => b.entries.compareTo(a.entries));

  // Cravings and ways of getting through them.
  final cravingEvents = [
    for (final e in all)
      if (e.type == RecoveryEventType.craving && range.contains(e.timestamp)) e,
  ];
  final intensities = [
    for (final e in cravingEvents)
      ((e.metadata['intensity'] as num?)?.round() ?? 5).clamp(0, 10),
  ];
  final triggerCounts = <String, int>{};
  final bandCounts = <int, int>{};
  for (final e in cravingEvents) {
    final trigger = ((e.metadata['trigger'] as String?) ?? 'Other').trim();
    triggerCounts.update(
      trigger.isEmpty ? 'Other' : trigger,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    bandCounts.update(
      TimeBand.of(e.timestamp).startHour,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  List<({String label, int count})> top(Map<String, int> m, int n) {
    final list = m.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return [for (final e in list.take(n)) (label: e.key, count: e.value)];
  }

  final outcomes = <String, int>{};
  var sos = 0;
  var code = 0;
  for (final e in all) {
    if (!range.contains(e.timestamp)) continue;
    if (e.type == RecoveryEventType.cravingCheck) {
      final o = e.metadata['outcome'];
      if (o is String) outcomes.update(o, (n) => n + 1, ifAbsent: () => 1);
    } else if (e.type == RecoveryEventType.sosComplete) {
      sos++;
    } else if (e.type == RecoveryEventType.codeSession &&
        e.metadata['completed'] == true) {
      code++;
    }
  }

  // Clean streaks on the lean/codeine timer (benzo-only never resets it).
  final starts =
      all
          .where((e) => e.type == RecoveryEventType.recoveryStart)
          .map((e) => e.timestamp)
          .toList()
        ..sort();
  final resets = [
    for (final e in all)
      if ((e.type == RecoveryEventType.relapse && resetsLeanCleanTimer(e)) ||
          (e.type == RecoveryEventType.recoveryStart &&
              e.metadata['source'] == 'legacyLastDose'))
        e.timestamp,
  ]..sort();
  final nowLocal = now.toLocal();
  final streaks = <ReportStreak>[];
  if (starts.isNotEmpty || resets.isNotEmpty) {
    final first = starts.isNotEmpty ? starts.first : resets.first;
    final points = <DateTime>[first, ...resets.where((r) => r.isAfter(first))];
    for (var i = 0; i < points.length; i++) {
      final from = points[i];
      final ongoing = i == points.length - 1;
      final to = ongoing ? nowLocal : points[i + 1];
      final clippedFrom = from.isBefore(range.start) ? range.start : from;
      final clippedTo = to.isAfter(range.endExclusive)
          ? range.endExclusive
          : to;
      if (!clippedTo.isAfter(clippedFrom)) continue;
      final days = clippedTo.difference(clippedFrom).inDays;
      if (days < 1) continue;
      streaks.add(
        ReportStreak(
          from: clippedFrom.toLocal(),
          to: clippedTo.toLocal(),
          days: days,
          ongoing: ongoing && !nowLocal.isAfter(range.endExclusive),
          startedBeforeRange: from.isBefore(range.start),
        ),
      );
    }
  }
  final longest = streaks.fold<int>(0, (m, s) => s.days > m ? s.days : m);

  final reportCheckIns = [
    for (final c in checkIns)
      if (range.contains(c.at))
        ReportCheckIn(
          at: c.at.toLocal(),
          symptoms: [
            for (final e in c.severities.entries)
              if (!e.key.isRedFlag)
                (label: e.key.label, severity: e.value.clamp(1, 3)),
          ],
          redFlags: [
            for (final e in c.severities.entries)
              if (e.key.isRedFlag) e.key.label,
          ],
        ),
  ]..sort((a, b) => a.at.compareTo(b.at));

  return DoctorReportData(
    range: range,
    generatedAt: now,
    entries: shownRows,
    entriesTotal: totalRows,
    totals: totals,
    mixedEntries: rows.where((r) => r.mixed).length,
    checkIns: reportCheckIns,
    cravings: ReportCravings(
      count: cravingEvents.length,
      averageIntensity: intensities.isEmpty
          ? 0
          : intensities.reduce((a, b) => a + b) / intensities.length,
      peakIntensity: intensities.isEmpty
          ? 0
          : intensities.reduce((a, b) => a > b ? a : b),
      topTriggers: top(triggerCounts, 5),
      topBands: [
        for (final e
            in (bandCounts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .take(3))
          (label: TimeBand(e.key).label, count: e.value),
      ],
      recheckOutcomes: outcomes,
      sosCompleted: sos,
      codeCompleted: code,
    ),
    streaks: streaks,
    longestStreakDays: longest,
    medicines: medicines.trim(),
    declaredSubstances: [
      if (companion != null)
        for (final s in companion.substances) s.label,
    ],
  );
}
