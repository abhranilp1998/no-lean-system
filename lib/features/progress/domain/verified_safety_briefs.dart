import '../../recovery/domain/recovery_event.dart';
import '../../recovery/domain/relapse_log_entry.dart';

enum VerifiedSafetyBriefKind {
  depressantMixing,
  reducedTolerance,
  counterfeitPills,
  overdoseResponse,
}

class VerifiedSafetyBrief {
  const VerifiedSafetyBrief({
    required this.kind,
    required this.title,
    required this.summary,
    required this.nextMove,
    required this.sourceLabel,
    required this.sourceUrl,
  });

  final VerifiedSafetyBriefKind kind;
  final String title;
  final String summary;
  final String nextMove;
  final String sourceLabel;
  final String sourceUrl;
}

const verifiedSafetyBriefs = <VerifiedSafetyBrief>[
  VerifiedSafetyBrief(
    kind: VerifiedSafetyBriefKind.depressantMixing,
    title: 'DO NOT STACK DOWNERS',
    summary:
        'Codeine or other opioids mixed with alcohol, benzodiazepines, or other sedatives can compound sleepiness and breathing suppression. The result can be coma or death.',
    nextMove:
        'Do not try to “balance” the mix. If breathing is slow, difficult, or the person cannot be awakened, treat it as an overdose.',
    sourceLabel: 'FDA // OPIOIDS + CNS DEPRESSANTS',
    sourceUrl:
        'https://www.fda.gov/drugs/information-drug-class/new-safety-measures-announced-opioid-analgesics-prescription-opioid-cough-products-and',
  ),
  VerifiedSafetyBrief(
    kind: VerifiedSafetyBriefKind.reducedTolerance,
    title: 'TOLERANCE IS NOT SAVED',
    summary:
        'After a period without opioids, tolerance can fall. Returning to an amount previously used can carry a much higher overdose risk.',
    nextMove:
        'Treat any return after clean time as a changed-risk situation. Put distance between the urge and access, and make naloxone part of the safety plan.',
    sourceLabel: 'NIDA // MEDICATIONS FOR OUD',
    sourceUrl:
        'https://nida.nih.gov/sites/default/files/21349-medications-to-treat-opioid-use-disorder.pdf',
  ),
  VerifiedSafetyBrief(
    kind: VerifiedSafetyBriefKind.counterfeitPills,
    title: 'A PILL CAN LIE',
    summary:
        'Illegally made fentanyl is often pressed into counterfeit pills or mixed into other drugs. Appearance cannot confirm what is inside.',
    nextMove:
        'Only take medication prescribed to you and dispensed by a licensed pharmacy. Naloxone can reverse an opioid overdose, including fentanyl.',
    sourceLabel: 'CDC // FENTANYL FACTS',
    sourceUrl: 'https://www.cdc.gov/overdose-prevention/about/fentanyl.html',
  ),
  VerifiedSafetyBrief(
    kind: VerifiedSafetyBriefKind.overdoseResponse,
    title: 'OVERDOSE: ACT, DO NOT GUESS',
    summary:
        'Warning signs include inability to wake, slow or shallow breathing, choking or gurgling sounds, discolored lips or nails, and pinpoint pupils.',
    nextMove:
        'Give naloxone if available, call emergency services, keep the person breathing, place them on their side, and stay until help arrives.',
    sourceLabel: 'CDC // OVERDOSE RESPONSE',
    sourceUrl: 'https://www.cdc.gov/stop-overdose/response/index.html',
  ),
];

class VerifiedSafetyInsight {
  const VerifiedSafetyInsight({
    required this.brief,
    required this.logMatched,
    required this.evidence,
    required this.priority,
  });

  final VerifiedSafetyBrief brief;
  final bool logMatched;
  final String evidence;
  final int priority;
}

/// Keeps medical guidance curated while ranking and explaining it from the
/// user's append-only recovery history. A match is a relevance signal, not a
/// diagnosis or proof that substances were used together.
List<VerifiedSafetyInsight> verifiedSafetyInsights({
  required Iterable<RecoveryEvent> events,
  required int cleanStreakDays,
}) {
  final relapses = events
      .where((event) => event.type == RecoveryEventType.relapse)
      .toList();
  final types = relapses
      .map((event) => RelapseTypeLabel.fromName(event.metadata['relapseType']))
      .whereType<RelapseType>()
      .toList();

  final opioidCount = types
      .where(
        (type) =>
            type == RelapseType.fullLean ||
            type == RelapseType.partial ||
            type == RelapseType.leanPlusAlcohol,
      )
      .length;
  final alcoholCount = types
      .where(
        (type) =>
            type == RelapseType.alcohol || type == RelapseType.leanPlusAlcohol,
      )
      .length;
  final benzoCount = types.where((type) => type == RelapseType.benzo).length;
  final explicitMixCount = types
      .where((type) => type == RelapseType.leanPlusAlcohol)
      .length;
  final depressantCount = relapses.where((event) {
    final type = RelapseTypeLabel.fromName(event.metadata['relapseType']);
    return type == null || type != RelapseType.other;
  }).length;
  final maxStreakLost = relapses.fold<int>(0, (largest, event) {
    final value = event.metadata['streakLost'];
    final days = value is num ? value.round() : 0;
    return days > largest ? days : largest;
  });
  final pillLanguageCount = relapses.where(_mentionsUnverifiedPill).length;

  final hasCrossLogMixSignal =
      (opioidCount > 0 && (alcoholCount > 0 || benzoCount > 0)) ||
      (alcoholCount > 0 && benzoCount > 0);
  final results = <VerifiedSafetyInsight>[];

  for (final brief in verifiedSafetyBriefs) {
    switch (brief.kind) {
      case VerifiedSafetyBriefKind.depressantMixing:
        if (explicitMixCount > 0) {
          results.add(
            VerifiedSafetyInsight(
              brief: brief,
              logMatched: true,
              evidence:
                  '$explicitMixCount logged event${explicitMixCount == 1 ? '' : 's'} explicitly selected LEAN + ALCOHOL.',
              priority: 400,
            ),
          );
        } else if (hasCrossLogMixSignal) {
          results.add(
            VerifiedSafetyInsight(
              brief: brief,
              logMatched: true,
              evidence:
                  'Your history contains opioid/lean, alcohol, or benzo categories across separate entries. That does not prove simultaneous use; it keeps the interaction warning visible.',
              priority: 390,
            ),
          );
        } else {
          results.add(
            VerifiedSafetyInsight(
              brief: brief,
              logMatched: false,
              evidence:
                  'No depressant-mixing signal is present in the structured logs.',
              priority: 40,
            ),
          );
        }
      case VerifiedSafetyBriefKind.reducedTolerance:
        final relevantDays = cleanStreakDays >= 3
            ? cleanStreakDays
            : maxStreakLost;
        if (relevantDays >= 3) {
          results.add(
            VerifiedSafetyInsight(
              brief: brief,
              logMatched: true,
              evidence: cleanStreakDays >= 3
                  ? 'Your current clean-time counter is $cleanStreakDays days. A return would follow a period without use.'
                  : 'A logged relapse followed a $maxStreakLost-day streak.',
              priority: 300 + relevantDays.clamp(0, 89),
            ),
          );
        } else {
          results.add(
            VerifiedSafetyInsight(
              brief: brief,
              logMatched: false,
              evidence:
                  'The logs do not yet show a clean interval long enough for a specific match.',
              priority: 30,
            ),
          );
        }
      case VerifiedSafetyBriefKind.counterfeitPills:
        if (pillLanguageCount > 0) {
          results.add(
            VerifiedSafetyInsight(
              brief: brief,
              logMatched: true,
              evidence:
                  '$pillLanguageCount relapse note${pillLanguageCount == 1 ? '' : 's'} mention pill/source language. The app cannot determine what a pill contained or where it came from.',
              priority: 350,
            ),
          );
        } else {
          results.add(
            VerifiedSafetyInsight(
              brief: brief,
              logMatched: false,
              evidence:
                  'No pill or source-related wording was found in relapse notes.',
              priority: 20,
            ),
          );
        }
      case VerifiedSafetyBriefKind.overdoseResponse:
        if (depressantCount > 0) {
          results.add(
            VerifiedSafetyInsight(
              brief: brief,
              logMatched: true,
              evidence:
                  '$depressantCount logged relapse event${depressantCount == 1 ? '' : 's'} involve a depressant category or a legacy event without substance detail. This does not mean an overdose occurred.',
              priority: 250 + depressantCount.clamp(0, 49),
            ),
          );
        } else {
          results.add(
            VerifiedSafetyInsight(
              brief: brief,
              logMatched: false,
              evidence:
                  'No depressant-related relapse is identified; emergency guidance remains available as a baseline.',
              priority: 10,
            ),
          );
        }
    }
  }

  results.sort((a, b) => b.priority.compareTo(a.priority));
  return List.unmodifiable(results);
}

bool _mentionsUnverifiedPill(RecoveryEvent event) {
  final searchable = [
    event.metadata['note'],
    event.metadata['quantity'],
  ].whereType<String>().join(' ').toLowerCase();
  if (searchable.isEmpty) return false;
  const signals = <String>[
    r'\bpills?\b',
    r'\btablets?\b',
    r'\bpressed\b',
    r'\bcounterfeit\b',
    r'\bdealer\b',
    r'\bxanax\b',
    r'\bperc(?:ocet)?s?\b',
    r'\boxy(?:codone|contin)?\b',
  ];
  return signals.any((signal) => RegExp(signal).hasMatch(searchable));
}
