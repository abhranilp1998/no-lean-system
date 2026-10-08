import 'recovery_event.dart';
import 'relapse_log_entry.dart';

/// Central nervous system depressant classes. Combining classes multiplies
/// breathing suppression (FDA boxed warning: opioids + benzodiazepines;
/// NIDA/CDC: opioids or benzos + alcohol).
enum DepressantClass { opioid, alcohol, benzo }

Set<DepressantClass> depressantClasses(RelapseType? type) => switch (type) {
  RelapseType.fullLean || RelapseType.partial => {DepressantClass.opioid},
  RelapseType.alcohol => {DepressantClass.alcohol},
  RelapseType.benzo => {DepressantClass.benzo},
  RelapseType.leanPlusAlcohol => {
    DepressantClass.opioid,
    DepressantClass.alcohol,
  },
  RelapseType.other || null => const {},
};

enum DoseWarningKind { mixing, repeatDose, tolerance }

class DoseWarning {
  const DoseWarning({
    required this.kind,
    required this.title,
    required this.body,
  });

  final DoseWarningKind kind;
  final String title;
  final String body;
}

String _classLabel(DepressantClass value) => switch (value) {
  DepressantClass.opioid => 'codeine/lean',
  DepressantClass.alcohol => 'alcohol',
  DepressantClass.benzo => 'benzos',
};

/// Warnings shown while logging. [draft] are the entries being logged now;
/// [events] is the saved history; [cleanStreakDays] is the streak that a
/// new relapse would end.
List<DoseWarning> loggingSafetyWarnings({
  required List<({RelapseType type, DateTime at})> draft,
  required Iterable<RecoveryEvent> events,
  required int cleanStreakDays,
  required DateTime now,
}) {
  if (draft.isEmpty) return const [];
  final relapses = events
      .where((e) => e.type == RecoveryEventType.relapse)
      .toList();
  final since = now.subtract(const Duration(hours: 24));
  final classes = <DepressantClass>{
    for (final entry in draft) ...depressantClasses(entry.type),
    for (final event in relapses)
      if (event.timestamp.isAfter(since))
        ...depressantClasses(
          RelapseTypeLabel.fromName(event.metadata['relapseType']),
        ),
  };
  String dayKey(DateTime at) {
    final local = at.toLocal();
    return '${local.year}-${local.month}-${local.day}';
  }

  final draftDays = draft.map((entry) => dayKey(entry.at)).toList();
  final repeatDay =
      draftDays.toSet().length < draftDays.length ||
      relapses.any((event) => draftDays.contains(dayKey(event.timestamp)));

  return [
    if (classes.length >= 2)
      DoseWarning(
        kind: DoseWarningKind.mixing,
        title: 'MIXING RISK',
        body:
            '${(classes.toList()..sort((a, b) => a.index.compareTo(b.index))).map(_classLabel).join(' + ')} in the same 24 hours. '
            'Each slows breathing; together the effect stacks and can stop it. '
            'Do not take more of anything tonight and do not use alone.',
      ),
    if (repeatDay)
      const DoseWarning(
        kind: DoseWarningKind.repeatDose,
        title: 'REPEAT DOSE SAME DAY',
        body:
            'This is not the first dose today. Levels build up: a second dose '
            'hits harder than the first. Stop here and keep someone close.',
      ),
    if (cleanStreakDays >= 3)
      DoseWarning(
        kind: DoseWarningKind.tolerance,
        title: 'TOLERANCE IS DOWN',
        body:
            'After $cleanStreakDays clean days your body is no longer used to '
            'your old amount. If you use again, the dose you used before can '
            'now cause an overdose. Do not use alone.',
      ),
  ];
}
