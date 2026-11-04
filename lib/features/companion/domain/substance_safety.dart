/// Safety copy tied to what the user says they use. Sources (checked
/// 4 Nov 2026): NHS diazepam, NICE CKS benzodiazepine withdrawal, NICE NG215,
/// MedlinePlus alcohol withdrawal (000764) and opioid withdrawal (000949).
/// No dosing, no taper schedules.
library;

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

List<SafetyNote> safetyNotesFor(CompanionState s, {bool recentSlip = false}) =>
    [if (s.needsTaperWarning) taperWarning, if (recentSlip) toleranceNote];
