/// Safety copy tied to what the user says they use. Sources (checked
/// 4 Nov 2026): NHS diazepam, NICE CKS benzodiazepine withdrawal, NICE NG215,
/// MedlinePlus alcohol withdrawal (000764) and opioid withdrawal (000949).
/// No dosing, no taper schedules.
library;

import '../../recovery/domain/recovery_event.dart';
import '../../recovery/domain/relapse_log_entry.dart';
import 'companion_state.dart';

class SafetyNote {
  const SafetyNote(this.title, this.body);
  final String title;
  final String body;
}

const taperWarning = SafetyNote(
  "Don't stop benzos or heavy drinking suddenly",
  'Lean (codeine) withdrawal is miserable but usually not life-threatening. Benzos '
      '(Valium, alprazolam and similar) and daily heavy drinking are '
      'different: stopping them suddenly can cause seizures or severe '
      'confusion. Cut down slowly with a doctor helping you. You can say '
      'exactly what you use; doctors deal with this every day.',
);

const redFlagNote = SafetyNote(
  'Go to a hospital now if you have',
  'A seizure or fit, confusion or seeing or hearing things that are not '
      'there, chest pain, fainting, not keeping fluids down for a day, or '
      'thoughts of ending your life. Call your SOS contact and get to the '
      'nearest hospital.',
);

const toleranceNote = SafetyNote(
  'Your tolerance is lower now',
  'After even a few days off, the old amount can be too much. Mixing with '
      'pills or alcohol makes it far riskier. Never use alone.',
);

/// Gentle check-in after a slip that mixed codeine with benzos or alcohol.
/// Mixing depressants multiplies breathing suppression (FDA boxed warning on
/// opioids + benzodiazepines; MedlinePlus).
const mixingCheckIn = SafetyNote(
  'Quick safety check after mixing',
  'Codeine with benzos or alcohol slows breathing more than either alone, '
      'and it can creep up hours later. Right now: are you very sleepy or '
      'hard to wake, breathing slowly, confused, being sick, or have you '
      'fainted? If yes, or if someone with you can\'t wake you properly, get '
      'to a hospital now and call your SOS contact. Either way, don\'t be '
      'alone tonight, don\'t take any more today, and lie on your side if you '
      'feel drowsy. Your tolerance is lower than it used to be.',
);

final _benzoWords = RegExp(
  r'\b(benzo\w*|valium|diazepam|alprazolam|alprax|xanax|clonazepam|'
  r'clonotril|rivotril|lorazepam|ativan|etizolam|nitrazepam|restyl|calmpose)\b',
  caseSensitive: false,
);
final _alcoholWords = RegExp(
  r'\b(alcohol|beer|whisky|whiskey|vodka|rum|wine|gin|daru|drinks?|drank|'
  r'drunk|peg|pegs)\b',
  caseSensitive: false,
);
final _codeineWords = RegExp(
  r'\b(codeine|lean|corex|phensedyl|ascoril[\s-]*c|tramadol)\b',
  caseSensitive: false,
);

/// Substances found in one logged event: its relapse type plus any note text.
Set<Substance> substancesInEvent(RecoveryEvent e) {
  final out = <Substance>{};
  if (e.type == RecoveryEventType.relapse) {
    switch (RelapseTypeLabel.fromName(e.metadata['relapseType'])) {
      case RelapseType.fullLean || RelapseType.partial:
        out.add(Substance.codeine);
      case RelapseType.alcohol:
        out.add(Substance.alcohol);
      case RelapseType.benzo:
        out.add(Substance.benzo);
      case RelapseType.leanPlusAlcohol:
        out.addAll({Substance.codeine, Substance.alcohol});
      default:
    }
  }
  final note = [
    e.metadata['note'],
    e.metadata['trigger'],
  ].whereType<String>().join(' ');
  if (note.isNotEmpty) {
    if (_benzoWords.hasMatch(note)) out.add(Substance.benzo);
    if (_alcoholWords.hasMatch(note)) out.add(Substance.alcohol);
    if (_codeineWords.hasMatch(note) && e.type == RecoveryEventType.relapse) {
      out.add(Substance.codeine);
    }
  }
  return out;
}

/// What the logs say, independent of the About-you answers.
class LoggedUse {
  const LoggedUse({
    this.benzo = false,
    this.heavyAlcohol = false,
    this.mixedSlip = false,
  });

  /// Any benzo use logged in the last 90 days.
  final bool benzo;

  /// Alcohol logged on 3+ separate days in the last 14 days.
  final bool heavyAlcohol;

  /// A slip in the last 72 h that combined codeine with benzos or alcohol
  /// (in one entry, entries within 24 h of each other, or a slip note).
  final bool mixedSlip;

  bool get needsTaper => benzo || heavyAlcohol;
}

LoggedUse loggedUse(
  Iterable<RecoveryEvent> events,
  DateTime now, {
  List<SlipNote> slips = const [],
}) {
  final used = [
    for (final e in events)
      if (e.type == RecoveryEventType.relapse ||
          e.metadata['note'] is String ||
          e.metadata['trigger'] is String)
        (
          at: e.timestamp,
          s: substancesInEvent(e),
          relapse: e.type == RecoveryEventType.relapse,
        ),
  ];
  bool within(DateTime t, Duration d) =>
      !t.isAfter(now.add(const Duration(minutes: 5))) && now.difference(t) <= d;

  final benzo =
      used.any(
        (u) =>
            u.s.contains(Substance.benzo) &&
            within(u.at, const Duration(days: 90)),
      ) ||
      slips.any(
        (n) =>
            n.substances.contains(Substance.benzo) &&
            within(n.at, const Duration(days: 90)),
      );

  final drinkDays = {
    for (final u in used)
      if (u.s.contains(Substance.alcohol) &&
          within(u.at, const Duration(days: 14)))
        DateTime(u.at.year, u.at.month, u.at.day),
    for (final n in slips)
      if (n.substances.contains(Substance.alcohol) &&
          within(n.at, const Duration(days: 14)))
        DateTime(n.at.year, n.at.month, n.at.day),
  };

  bool mixes(Set<Substance> s) =>
      s.contains(Substance.codeine) &&
      (s.contains(Substance.benzo) || s.contains(Substance.alcohol));

  var mixed = slips.any(
    (n) => within(n.at, const Duration(hours: 72)) && mixes(n.substances),
  );
  final recent = [
    for (final u in used)
      if (u.relapse && within(u.at, const Duration(hours: 72))) u,
  ];
  for (final a in recent) {
    if (mixed) break;
    final around = <Substance>{
      for (final b in used)
        if (b.relapse &&
            b.at.difference(a.at).abs() <= const Duration(hours: 24))
          ...b.s,
    };
    mixed = mixes(around);
  }
  return LoggedUse(
    benzo: benzo,
    heavyAlcohol: drinkDays.length >= 3,
    mixedSlip: mixed,
  );
}

/// The taper warning shows when the user picked benzos / heavy drinking OR
/// the logs show them.
bool needsTaperWarning(
  CompanionState s,
  Iterable<RecoveryEvent> events,
  DateTime now,
) => s.needsTaperWarning || loggedUse(events, now, slips: s.slips).needsTaper;

List<SafetyNote> safetyNotesFor(
  CompanionState s, {
  bool recentSlip = false,
  Iterable<RecoveryEvent> events = const [],
  DateTime? now,
}) {
  final logged = loggedUse(events, now ?? DateTime.now(), slips: s.slips);
  return [
    if (logged.mixedSlip) mixingCheckIn,
    if (s.needsTaperWarning || logged.needsTaper) taperWarning,
    if (recentSlip && !logged.mixedSlip) toleranceNote,
  ];
}
