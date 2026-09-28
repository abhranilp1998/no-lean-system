class VerifiedSafetyBrief {
  const VerifiedSafetyBrief({
    required this.title,
    required this.summary,
    required this.nextMove,
    required this.sourceLabel,
    required this.sourceUrl,
  });

  final String title;
  final String summary;
  final String nextMove;
  final String sourceLabel;
  final String sourceUrl;
}

const verifiedSafetyBriefs = <VerifiedSafetyBrief>[
  VerifiedSafetyBrief(
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
    title: 'A PILL CAN LIE',
    summary:
        'Illegally made fentanyl is often pressed into counterfeit pills or mixed into other drugs. Appearance cannot confirm what is inside.',
    nextMove:
        'Only take medication prescribed to you and dispensed by a licensed pharmacy. Naloxone can reverse an opioid overdose, including fentanyl.',
    sourceLabel: 'CDC // FENTANYL FACTS',
    sourceUrl: 'https://www.cdc.gov/overdose-prevention/about/fentanyl.html',
  ),
  VerifiedSafetyBrief(
    title: 'OVERDOSE: ACT, DO NOT GUESS',
    summary:
        'Warning signs include inability to wake, slow or shallow breathing, choking or gurgling sounds, discolored lips or nails, and pinpoint pupils.',
    nextMove:
        'Give naloxone if available, call emergency services, keep the person breathing, place them on their side, and stay until help arrives.',
    sourceLabel: 'CDC // OVERDOSE RESPONSE',
    sourceUrl: 'https://www.cdc.gov/stop-overdose/response/index.html',
  ),
];
