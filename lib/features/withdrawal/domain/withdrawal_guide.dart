/// Offline withdrawal guidance for short-acting opioids such as codeine.
/// Content summarised from MedlinePlus, NIH StatPearls, WHO, SAMHSA and NICE.
/// It is general information, not medical advice.
library;

class WithdrawalStage {
  const WithdrawalStage({
    required this.id,
    required this.title,
    required this.startHour,
    required this.endHour,
    required this.normalNow,
    required this.comingNext,
  });

  final String id;
  final String title;
  final int startHour;
  final int? endHour;
  final String normalNow;
  final String comingNext;
}

const withdrawalStages = <WithdrawalStage>[
  WithdrawalStage(
    id: 'early',
    title: 'First hours',
    startHour: 0,
    endHour: 24,
    normalNow:
        'From about 6–12 hours: restlessness, anxiety, yawning, watery eyes, '
        'runny nose, sweating, aching muscles and trouble sleeping.',
    comingNext:
        'Over the next day symptoms usually build. Stomach cramps, loose '
        'stools and chills may start. Stock up on water, ORS and simple food now.',
  ),
  WithdrawalStage(
    id: 'peak',
    title: 'The peak (day 1 to 3)',
    startHour: 24,
    endHour: 72,
    normalNow:
        'This is usually the hardest stretch: cramps, diarrhoea, nausea or '
        'vomiting, goosebumps, hot and cold spells, aches, strong cravings and '
        'poor sleep. The main danger is losing fluids from vomiting and '
        'diarrhoea, so keep sipping. Going through it alone can be risky; '
        'have someone check on you. Fainting, chest pain, confusion or not '
        'keeping fluids down: go to a hospital or call your SOS contact.',
    comingNext:
        'Most people start to feel the worst lift between day 3 and day 5. '
        'Keep sipping fluids and resting; each hour you get through counts.',
  ),
  WithdrawalStage(
    id: 'easing',
    title: 'Easing (day 3 to 7)',
    startHour: 72,
    endHour: 168,
    normalNow:
        'Physical symptoms are fading. Tiredness, low mood, poor sleep and '
        'cravings can hang on.',
    comingNext:
        'By around day 7 (sometimes up to day 10) most body symptoms are gone. '
        'Sleep and mood take longer, so plan your days and lean on support.',
  ),
  WithdrawalStage(
    id: 'post_acute',
    title: 'Weeks after',
    startHour: 168,
    endHour: null,
    normalNow:
        'Body is mostly through it. Low mood, anxiety, broken sleep and '
        'cravings can come in waves for weeks or months, then fade.',
    comingNext:
        'Waves get shorter and further apart. This is when slips are most '
        'likely, so keep your plan, triggers list and support close.',
  ),
];

WithdrawalStage stageFor(Duration clean) {
  final h = clean.inHours;
  return withdrawalStages.lastWhere((s) => h >= s.startHour);
}

/// Plain sentence about when the hard part should ease.
String easesText(Duration clean) {
  final h = clean.inHours;
  if (h < 72) {
    final toDay3 = 72 - h;
    return 'The worst usually starts easing in about $toDay3 hours (around day 3–5).';
  }
  if (h < 168) {
    return 'Body symptoms usually settle within ${168 - h} more hours (around day 7).';
  }
  return 'The physical part is usually over. Mood and sleep keep improving over weeks.';
}

enum Symptom {
  anxiety('Anxious / restless'),
  aches('Body aches'),
  sleep('Can\'t sleep'),
  runnyNose('Runny nose / yawning'),
  sweats('Sweats / chills'),
  cramps('Stomach cramps'),
  diarrhoea('Diarrhoea'),
  vomiting('Nausea / vomiting'),
  cravings('Cravings'),
  lowMood('Low mood'),
  // Red flags.
  cantKeepFluids('Can\'t keep fluids down'),
  dizzyFaint('Dizzy / fainting'),
  chestPain('Chest pain'),
  blood('Blood in vomit or stool'),
  confusion('Confused / seizure'),
  selfHarm('Thoughts of hurting myself');

  const Symptom(this.label);
  final String label;

  bool get isRedFlag => index >= Symptom.cantKeepFluids.index;
}

class SymptomCheckIn {
  const SymptomCheckIn({required this.at, required this.severities});

  final DateTime at;

  /// Severity 1 (mild) to 3 (severe).
  final Map<Symptom, int> severities;

  bool get hasRedFlag =>
      severities.keys.any((s) => s.isRedFlag) ||
      (severities[Symptom.vomiting] ?? 0) >= 3 &&
          (severities[Symptom.diarrhoea] ?? 0) >= 3;

  Map<String, Object> toJson() => {
    'at': at.toIso8601String(),
    's': {for (final e in severities.entries) e.key.name: e.value},
  };

  static SymptomCheckIn? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at']}');
    final s = raw['s'];
    if (at == null || s is! Map) return null;
    final out = <Symptom, int>{};
    for (final e in s.entries) {
      final sym = Symptom.values.where((v) => v.name == e.key).firstOrNull;
      final v = e.value;
      if (sym != null && v is int) out[sym] = sym.isRedFlag ? 1 : v.clamp(1, 3);
    }
    return SymptomCheckIn(at: at, severities: out);
  }
}

class GuideTip {
  const GuideTip(this.title, this.body);
  final String title;
  final String body;
}

const notMedicalAdvice =
    'General information, not medical advice. Check with a doctor or '
    'pharmacist before taking any medicine, especially if you have other '
    'health conditions or take other medicines.';

const generalDos = <String>[
  'Sip water or ORS little and often, even if you don\'t feel thirsty.',
  'Eat small, bland meals: banana, rice, curd, toast, khichdi.',
  'Rest, warm bath or shower, hot water bottle for cramps.',
  'Short walks and fresh air help restlessness.',
  'Tell one trusted person how you\'re doing today.',
  'A doctor can prescribe medicines that make withdrawal much easier. Asking is a strong move.',
];

const generalDonts = <String>[
  'Don\'t take leftover syrup or any other opioid. After even a few days off, your tolerance drops, so your old dose can cause an overdose.',
  'No alcohol, sleeping pills or anxiety pills (like alprazolam) without a doctor; mixing them can slow breathing.',
  'Don\'t drive or operate machines if you are dizzy or exhausted.',
  'Read labels: many cough syrups contain codeine or sedating antihistamines.',
];

/// OTC suggestions tailored to logged symptoms. Always shown with
/// [notMedicalAdvice].
List<GuideTip> reliefFor(Set<Symptom> s) {
  final tips = <GuideTip>[];
  if (s.contains(Symptom.diarrhoea) || s.contains(Symptom.vomiting)) {
    tips.add(
      const GuideTip(
        'ORS for fluids',
        'Oral rehydration salts in clean water, sipped often. Most important thing when you have diarrhoea or vomiting.',
      ),
    );
  }
  if (s.contains(Symptom.diarrhoea)) {
    tips.add(
      const GuideTip(
        'Loperamide for diarrhoea',
        'Adults: follow the pack (usually 4 mg first, then 2 mg after each loose stool, max 12 mg in 24 hours and no more than 2 days without a doctor). Never take more: high doses can cause dangerous heart rhythm problems. Don\'t use with fever or blood in stool.',
      ),
    );
  }
  if (s.contains(Symptom.aches) || s.contains(Symptom.cramps)) {
    tips.add(
      const GuideTip(
        'Paracetamol or ibuprofen for aches',
        'Paracetamol: max 4 g a day for adults, less if you drink alcohol or have liver problems. Ibuprofen: take with food; avoid with stomach ulcers, kidney problems or if it worsens your asthma.',
      ),
    );
  }
  if (s.contains(Symptom.sleep) || s.contains(Symptom.runnyNose)) {
    tips.add(
      const GuideTip(
        'Antihistamines: use with care',
        'Some (like cetirizine) help a runny nose. Sedating ones can help sleep for a night or two but cause next-day drowsiness. Never mix with alcohol or other sedatives. Don\'t use cough syrups.',
      ),
    );
  }
  if (s.contains(Symptom.anxiety) || s.contains(Symptom.cravings)) {
    tips.add(
      const GuideTip(
        'For restlessness and cravings',
        'Slow breathing, a cold-water face splash, a walk, or SOS mode in this app. Cravings peak and pass in waves of minutes.',
      ),
    );
  }
  return tips;
}

const prescriptionNote =
    'Doctor-only options: clonidine, lofexidine, buprenorphine, methadone and '
    'anti-sickness medicines can ease withdrawal a lot, but only a doctor can '
    'prescribe them.';

const redFlagText =
    'Some of what you logged needs a doctor today. Please see a doctor or go '
    'to the nearest hospital, especially for chest pain, a seizure, confusion, '
    'blood in vomit or stool, fainting, slow or shallow breathing, or not '
    'keeping fluids down for a day. If you feel unsafe or think of hurting '
    'yourself, open SOS or call your trusted contact now. You don\'t have to '
    'get through this alone.';

class GuideSource {
  const GuideSource(this.name, this.url);
  final String name;
  final String url;
}

class InfoSection {
  const InfoSection(this.title, this.items);
  final String title;
  final List<String> items;
}

/// Hour-by-hour detail for the full stage view.
const detailedStages = <InfoSection>[
  InfoSection('0–6 hours', [
    'Usually still comfortable.',
    'First cravings, worry and restlessness.',
    'Good time to prepare: ORS, water, simple food, a clean room, a plan for tonight.',
  ]),
  InfoSection('6–12 hours', [
    'Yawning, watery eyes, runny nose, sweating.',
    'Restless legs, anxiety, irritability.',
    'Codeine wears off fast (half-life about 3 hours), so signs start early.',
  ]),
  InfoSection('12–24 hours', [
    'Muscle and bone aches, goosebumps, hot and cold flushes.',
    'Dilated pupils, poor sleep.',
    'Antihistamines in the syrup (like chlorpheniramine) leave more slowly, so sleep and runny nose can lag a day or two.',
  ]),
  InfoSection('24–48 hours', [
    'Peak begins: stomach cramps, diarrhoea, nausea or vomiting.',
    'Strongest cravings, fast pulse, sweating, insomnia.',
    'Dehydration is the main physical risk. Keep sipping ORS.',
  ]),
  InfoSection('48–72 hours', [
    'Most people feel worst here.',
    'Same symptoms as the peak, often with exhaustion.',
    'Higher doses or years of use can push the peak to day 4.',
  ]),
  InfoSection('Day 3–5', [
    'Physical symptoms start lifting.',
    'Tired, low appetite, poor sleep, cravings still come in waves.',
  ]),
  InfoSection('Day 5–7', [
    'Most body symptoms gone for typical doses.',
    'Sleep and mood are still catching up.',
  ]),
  InfoSection('Day 7–14', [
    'Heavy or long-term users may still have aches, gut upset and insomnia.',
    'Rebound sleep problems from antihistamines usually settle.',
  ]),
  InfoSection('Weeks 2–4 (PAWS starts)', [
    'Low mood, anxiety, low energy, poor focus, broken sleep.',
    'Cravings triggered by places, people, evenings and stress.',
  ]),
  InfoSection('Months 1–6', [
    'Waves get shorter and further apart.',
    'Exercise, routine, sleep and talking to someone speed it up.',
    'Relapse risk is highest here and tolerance is low: an old dose can be an overdose.',
  ]),
];

const infoSections = <InfoSection>[
  InfoSection('What changes how bad it gets', [
    'Higher daily dose and more years of use mean stronger, longer symptoms.',
    'Stop-start use restarts the clock; a short slip usually gives a milder round.',
    'Tapering with a doctor (or buprenorphine-assisted withdrawal) is gentler than stopping at once. Stopping at once is harder; the main risk is dehydration from vomiting and diarrhoea, and withdrawing alone can be dangerous. If you also take benzos (Valium, alprazolam) or drink heavily every day, never stop those suddenly: that can cause seizures, so taper with a doctor.',
    'Heart problems, epilepsy, pregnancy or mental health conditions need a doctor before stopping.',
  ]),
  InfoSection('Over-the-counter relief (adults)', [
    'ORS: one sachet in the stated amount of clean water; sip after each loose stool.',
    'Paracetamol: 500 mg–1 g every 4–6 hours, max 4 g in 24 hours (less with liver problems, low weight or regular alcohol).',
    'Ibuprofen: 200–400 mg every 6–8 hours with food, max 1,200 mg a day; avoid with ulcers, kidney or heart problems, some asthma, pregnancy.',
    'Loperamide: 4 mg, then 2 mg after each loose stool; max 12 mg in 24 hours, no more than 2 days. Never more: risk of dangerous heart rhythms. Not with fever or blood in stool.',
    'Hyoscine butylbromide (for cramps): 10–20 mg up to 4 times a day; not with glaucoma or trouble passing urine.',
    'Cetirizine 10 mg once a day for runny nose. Sedating antihistamines only for an occasional night; never with alcohol or other sedatives.',
    'Avoid all cough syrups.',
  ]),
  InfoSection('Doctor-only options', [
    'Buprenorphine or methadone (supervised withdrawal or maintenance).',
    'Clonidine or lofexidine for sweats, restlessness and cramps.',
    'Anti-sickness medicines and short-term sleep help.',
  ]),
  InfoSection('Sleep', [
    'Same bedtime and wake time, even after a bad night.',
    'Dark, cool room; phone out of reach; no caffeine after noon.',
    'Warm shower before bed relaxes aching muscles.',
    'Resting with eyes closed still helps if sleep won\'t come.',
    'Avoid sleeping pills and alcohol unless a doctor prescribes them.',
  ]),
  InfoSection('Food and hydration', [
    'Aim for pale yellow urine; sip water or ORS all day.',
    'Small bland meals: banana, rice, curd, khichdi, toast, dal.',
    'Coconut water and soups help replace salts.',
    'Skip spicy, oily food and lots of sugar during the peak.',
  ]),
  InfoSection('Red flags: see a doctor or go to the nearest hospital', [
    'Can\'t keep fluids down for a day, very little dark urine, dizziness or fainting.',
    'Blood in vomit or stool, chest pain or a racing heart.',
    'Seizure, confusion, high fever.',
    'Slow or shallow breathing or hard to wake after any use: emergency now.',
    'Thoughts of hurting yourself: open SOS and reach your trusted contact now.',
  ]),
  InfoSection('PAWS (post-acute withdrawal)', [
    'Weeks to months of up-and-down mood, anxiety, low energy, poor sleep and cravings.',
    'It is a normal part of the brain healing, not failure.',
    'Routine, movement, sunlight, protein-rich food and talking to someone help.',
    'Keep your triggers list and evening plan close; cravings pass in minutes.',
  ]),
];

const guideSources = <GuideSource>[
  GuideSource(
    'StatPearls (NIH): Codeine',
    'https://www.ncbi.nlm.nih.gov/books/NBK526029/',
  ),
  GuideSource(
    'StatPearls (NIH): Promethazine',
    'https://www.ncbi.nlm.nih.gov/books/NBK544361/',
  ),
  GuideSource(
    'MedlinePlus: Chlorpheniramine',
    'https://medlineplus.gov/druginfo/meds/a682543.html',
  ),
  GuideSource(
    'SAMHSA: Protracted Withdrawal advisory',
    'https://store.samhsa.gov/product/advisory-protracted-withdrawal/sma10-4554',
  ),
  GuideSource(
    'Wesson & Ling 2003: COWS scale',
    'https://pubmed.ncbi.nlm.nih.gov/12924748/',
  ),
  GuideSource(
    'Mattoo et al. 1997: Codeine cough syrup abuse in India',
    'https://pubmed.ncbi.nlm.nih.gov/9581010/',
  ),
  GuideSource(
    'Indian J Med Sci 1999: Subtypes of codeine syrup users',
    'https://pubmed.ncbi.nlm.nih.gov/10798008/',
  ),
  GuideSource(
    'NHS: Paracetamol',
    'https://www.nhs.uk/medicines/paracetamol-for-adults/',
  ),
  GuideSource(
    'NHS: Ibuprofen',
    'https://www.nhs.uk/medicines/ibuprofen-for-adults/',
  ),
  GuideSource(
    'MedlinePlus (NIH): Opiate and opioid withdrawal',
    'https://medlineplus.gov/ency/article/000949.htm',
  ),
  GuideSource(
    'StatPearls (NIH): Opioid Withdrawal',
    'https://www.ncbi.nlm.nih.gov/books/NBK526012/',
  ),
  GuideSource(
    'WHO: Treatment of opioid dependence guidelines',
    'https://www.ncbi.nlm.nih.gov/books/NBK143185/',
  ),
  GuideSource(
    'SAMHSA TIP 63',
    'https://store.samhsa.gov/product/tip-63-medications-opioid-use-disorder/pep21-02-01-002',
  ),
  GuideSource(
    'NICE CG52: Opioid detoxification',
    'https://www.nice.org.uk/guidance/cg52',
  ),
  GuideSource('NHS: Loperamide', 'https://www.nhs.uk/medicines/loperamide/'),
];
