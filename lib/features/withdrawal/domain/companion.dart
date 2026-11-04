/// Warm companion copy: greeting, acknowledgement, empathy, next move.
library;

import 'withdrawal_guide.dart';
import 'withdrawal_personal.dart';

enum Comfort { unset, yes, later, no }

class CompanionPrefs {
  const CompanionPrefs({
    this.name = '',
    this.doctor = Comfort.unset,
    this.supportLine = Comfort.unset,
    this.supportNumber = '',
  });
  final String name;
  final Comfort doctor;
  final Comfort supportLine;

  /// User-entered. No default number.
  final String supportNumber;

  bool get asked => doctor != Comfort.unset && supportLine != Comfort.unset;
  bool get showSupportLine =>
      supportLine == Comfort.yes && supportNumber.trim().isNotEmpty;

  CompanionPrefs copyWith({
    String? name,
    Comfort? doctor,
    Comfort? supportLine,
    String? supportNumber,
  }) => CompanionPrefs(
    name: name ?? this.name,
    doctor: doctor ?? this.doctor,
    supportLine: supportLine ?? this.supportLine,
    supportNumber: supportNumber ?? this.supportNumber,
  );

  Map<String, Object> toJson() => {
    'name': name,
    'doctor': doctor.name,
    'supportLine': supportLine.name,
    'supportNumber': supportNumber,
  };

  static CompanionPrefs fromJson(Object? raw) {
    if (raw is! Map) return const CompanionPrefs();
    Comfort c(Object? v) =>
        Comfort.values.where((e) => e.name == v).firstOrNull ?? Comfort.unset;
    String s(Object? v, int max) =>
        v is String ? (v.length > max ? v.substring(0, max) : v) : '';
    return CompanionPrefs(
      name: s(raw['name'], 40),
      doctor: c(raw['doctor']),
      supportLine: c(raw['supportLine']),
      supportNumber: s(raw['supportNumber'], 20),
    );
  }
}

String greeting(DateTime now, String name) {
  final h = now.hour;
  final part = h < 5
      ? 'Still up'
      : h < 12
      ? 'Good morning'
      : h < 17
      ? 'Good afternoon'
      : h < 22
      ? 'Good evening'
      : 'Late night';
  final n = name.trim();
  return n.isEmpty ? '$part.' : '$part, $n.';
}

String _pick(List<String> options, DateTime now) =>
    options[(now.day * 24 + now.hour) % options.length];

String acknowledgement(PersonalPlan p, DateTime now) {
  final h = p.sinceLastUse.inHours;
  final d = p.sinceLastUse.inDays;
  if (p.inRelapse) {
    return _pick([
      'You came back, and that counts. No shame here, just the next hour.',
      'A slip doesn\'t erase what you learned. You\'re here now, that matters.',
      'You opened this instead of giving up. That is the comeback.',
    ], now);
  }
  if (h < 12) {
    return _pick([
      '$h hours in. The first steps are the bravest ones.',
      '$h hours clean. You chose this. Good job.',
    ], now);
  }
  if (h < 24) {
    return _pick([
      '$h hours clean. You\'re heading into the hard part with your eyes open.',
      '$h hours. That is real progress, well done.',
    ], now);
  }
  if (h < 72) {
    final night = h >= 30 ? ' You got through the hardest night.' : '';
    return _pick([
      '$h hours clean.$night Good job.',
      '$h hours. This is the toughest stretch and you\'re still standing.$night',
      'Day ${d + 1}, $h hours.$night Proud of you.',
    ], now);
  }
  if (d < 7) {
    return _pick([
      'Day ${d + 1}. You\'re past the peak. Your body is healing.',
      '$d days clean. The worst is behind you. Good job.',
    ], now);
  }
  if (d < 30) {
    return _pick([
      '$d days clean. Over a week. That is huge.',
      '$d days. You did the hard part; now we protect it.',
    ], now);
  }
  return _pick([
    '$d days clean. You built this one day at a time.',
    '$d days. Steady and strong.',
  ], now);
}

String empathy(PersonalPlan p, SymptomCheckIn? latest) {
  final s = latest?.severities ?? const {};
  final heavy = s.values.where((v) => v >= 3).length;
  final h = p.sinceLastUse.inHours;
  if (latest?.hasRedFlag ?? false) {
    return 'Some of what you logged needs a doctor. Please don\'t carry this alone.';
  }
  if (h >= p.course.peakStartH && h < p.course.peakEndH) {
    return heavy > 0
        ? 'This is the toughest stretch, and it\'s normal to feel wrecked. It does pass.'
        : 'You\'re in the peak window. Feeling rough is expected; it\'s your body resetting.';
  }
  if (s.containsKey(Symptom.lowMood) || s.containsKey(Symptom.anxiety)) {
    return 'Low or jumpy moods are part of healing, not a sign you\'re failing.';
  }
  if (h < p.course.peakStartH) {
    return 'Things may build over the next day. Getting ready now makes it easier.';
  }
  return 'Your body has done the heavy lifting. Be patient with sleep and mood.';
}

class NextMove {
  const NextMove(this.title, this.detail);
  final String title;
  final String detail;
}

NextMove nextMove(
  PersonalPlan p,
  SymptomCheckIn? latest,
  DateTime now, {
  bool inRiskWindow = false,
}) {
  final s = latest?.severities ?? const {};
  if (latest?.hasRedFlag ?? false) {
    return const NextMove(
      'See a doctor today',
      'Go to a doctor or the nearest hospital. Open SOS to reach your trusted contact.',
    );
  }
  if (s.containsKey(Symptom.cravings) || inRiskWindow || p.inRelapse) {
    return const NextMove(
      'Ride out the craving wave',
      'Cravings peak and pass within minutes. Open SOS, breathe for 60 seconds, then move rooms.',
    );
  }
  if (s.containsKey(Symptom.diarrhoea) || s.containsKey(Symptom.vomiting)) {
    return const NextMove(
      'Drink ORS now',
      'A few sips every few minutes. Aim for a glass after each loose stool.',
    );
  }
  if (s.containsKey(Symptom.aches) || s.containsKey(Symptom.sweats)) {
    return const NextMove(
      'Hot shower for aches',
      '10 minutes of warm water eases muscle aches and chills.',
    );
  }
  if (now.hour >= 22 || now.hour < 5 || s.containsKey(Symptom.sleep)) {
    return const NextMove(
      'Wind down for sleep',
      'Dim lights, phone away, warm drink (no caffeine). Lying down resting still counts if sleep won\'t come.',
    );
  }
  if (s.containsKey(Symptom.lowMood) || s.containsKey(Symptom.anxiety)) {
    return const NextMove(
      'Text your trusted contact',
      'Just "rough day, thinking of you" is enough.',
    );
  }
  if (now.hour >= 7 && now.hour < 20) {
    return p.sinceLastUse.inHours < 72
        ? const NextMove(
            'Eat something light',
            'Banana, curd rice, khichdi or toast. Small and often.',
          )
        : const NextMove(
            'Take a short walk',
            '10 minutes outside lifts mood and helps sleep later.',
          );
  }
  return const NextMove(
    'Sip water and rest',
    'Keep a bottle and ORS by your bed.',
  );
}

/// What to tell a doctor, built from logs.
List<String> doctorBrief(PersonalPlan p, SymptomCheckIn? latest) => [
  'I\'ve been using codeine cough syrup${p.dose.avgMlPerUseDay != null ? ', about ${p.dose.avgMlPerUseDay!.round()} ml a day' : ''}'
      '${p.dose.spanDays > 0 ? ' (logged over ${p.dose.spanDays} days)' : ''}.',
  'My last dose was ${p.sinceLastUse.inHours} hours ago.',
  if (latest != null && latest.severities.isNotEmpty)
    'Right now: ${latest.severities.keys.map((e) => e.label.toLowerCase()).join(', ')}.',
  'Mention any other medicines, alcohol or health conditions.',
];

const doctorAskAbout =
    'You can ask about: buprenorphine or a supervised taper, clonidine or '
    'lofexidine for sweats and restlessness, anti-sickness medicine, and help '
    'with sleep.';
