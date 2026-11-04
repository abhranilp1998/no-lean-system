/// Bundled, offline companion message library. Friendly, specific, no hype,
/// no shame. Placeholders: {name} {hours} {days} {easeIn} {best} {saved}
/// {contact}. Empty tag sets mean "any".
library;

enum MsgKind { greet, praise, normalise, together, craving, lapse, night, paws }

class CompanionMessage {
  const CompanionMessage(
    this.id,
    this.kind,
    this.text, {
    this.bands = const {},
    this.tods = const {},
    this.symptoms = const {},
    this.moods = const {},
    this.minCraving = 0,
    this.lapse = false,
  });
  final String id;
  final MsgKind kind;
  final String text;
  final Set<String> bands;
  final Set<String> tods;
  final Set<String> symptoms;
  final Set<String> moods;
  final int minCraving;

  /// Only for a recent slip (and never otherwise).
  final bool lapse;

  int get specificity =>
      (bands.isEmpty ? 0 : 2) +
      (tods.isEmpty ? 0 : 1) +
      (symptoms.isEmpty ? 0 : 3) +
      (moods.isEmpty ? 0 : 2) +
      (minCraving > 0 ? 2 : 0);
}

const bandIds = {
  'h0_12',
  'h12_24',
  'h24_48',
  'h48_72',
  'd3_5',
  'd5_7',
  'd7_14',
  'w2_4',
  'm1_3',
  'm3plus',
};
const todIds = {'morning', 'afternoon', 'evening', 'night'};
const symptomIds = {
  'aches',
  'gut',
  'sweats',
  'sleep',
  'anxiety',
  'restless',
  'lowmood',
  'cravings',
};
const moodIds = {'low', 'anxious', 'irritable', 'numb', 'okay', 'good'};

const _early = {'h0_12', 'h12_24'};
const _peak = {'h24_48', 'h48_72'};
const _late = {'d3_5', 'd5_7'};
const _weeks = {'d7_14'};
const _long = {'w2_4', 'm1_3', 'm3plus'};

typedef _M = CompanionMessage;
const _g = MsgKind.greet;
const _p = MsgKind.praise;
const _n = MsgKind.normalise;
const _t = MsgKind.together;
const _c = MsgKind.craving;
const _l = MsgKind.lapse;
const _e = MsgKind.night;
const _w = MsgKind.paws;

const companionMessages = <CompanionMessage>[
  // ---------- Greetings ----------
  _M(
    'g01',
    _g,
    "Morning, {name}. You made it through the night. That's {hours} hours. Let's just do this morning.",
    tods: {'morning'},
  ),
  _M(
    'g02',
    _g,
    "Hey {name}. {hours} hours. However you feel right now, you're still here, still doing it.",
    tods: {'afternoon'},
  ),
  _M(
    'g03',
    _g,
    'Evening, {name}. Evenings can be the hardest bit. We take it one hour at a time.',
    tods: {'evening'},
  ),
  _M(
    'g04',
    _g,
    "Still up, {name}? Nights like this are long. You don't have to sleep, just rest. I'm here.",
    tods: {'night'},
  ),
  _M(
    'g05',
    _g,
    "Hi {name}. Hour {hours}. This is the hard part, and you're in it, not stuck in it.",
    bands: _peak,
  ),
  _M(
    'g06',
    _g,
    "Hey {name}, good to see you. Day {days}. Your body's doing quiet repair work, even on flat days.",
    bands: _long,
  ),
  _M(
    'g07',
    _g,
    "Morning, {name}. New day, same plan: water, food, one small win.",
    tods: {'morning'},
  ),
  _M(
    'g08',
    _g,
    "Hey {name}. Checking in is a good move. Let's see what today needs.",
    tods: {'afternoon'},
  ),
  _M(
    'g09',
    _g,
    "Evening, {name}. If the old routine is calling, we've got a different plan tonight.",
    tods: {'evening'},
  ),
  _M(
    'g10',
    _g,
    "It's late, {name}. Late is when the mind gets loud. Keep it simple: lie down, breathe, wait it out.",
    tods: {'night'},
  ),
  _M(
    'g11',
    _g,
    "Hey {name}. Early hours. Get water and snacks near you now, while it's still easy.",
    bands: _early,
  ),
  _M(
    'g12',
    _g,
    "Morning, {name}. If the night was rough, that's normal for hour {hours}. You still got through it.",
    tods: {'morning'},
    bands: _peak,
  ),
  _M(
    'g13',
    _g,
    "Hi {name}. Day {days}. The worst of the body stuff is usually behind you by now.",
    bands: _late,
  ),
  _M(
    'g14',
    _g,
    "Hey {name}. Over a week. Let's keep things boring and steady today.",
    bands: _weeks,
  ),
  _M(
    'g15',
    _g,
    "Afternoon, {name}. Have you eaten? Even a banana counts.",
    tods: {'afternoon'},
    bands: {..._peak, ..._late},
  ),
  _M(
    'g16',
    _g,
    "Evening, {name}. {hours} hours. Tonight you only need to get to the morning.",
    tods: {'evening'},
    bands: _peak,
  ),
  _M(
    'g17',
    _g,
    "Hey {name}. Long nights are when it hurts most. Let's make this one a bit easier.",
    tods: {'night'},
    bands: _peak,
  ),
  _M(
    'g18',
    _g,
    'Morning, {name}. {days} days. Same wake-up time as yesterday? That helps sleep come back.',
    tods: {'morning'},
    bands: _long,
  ),
  _M(
    'g19',
    _g,
    "Hey {name}. Whatever today looks like, you don't have to fix everything. Just the next hour.",
    moods: {'low', 'numb'},
  ),
  _M(
    'g20',
    _g,
    "Hey {name}. Feeling wired? Let's take some of that edge off together.",
    moods: {'anxious', 'irritable'},
  ),
  _M(
    'g21',
    _g,
    "Hi {name}. Good to hear you're feeling okay. Let's use it: one thing that makes tomorrow easier.",
    moods: {'okay', 'good'},
  ),
  _M(
    'g22',
    _g,
    "Evening, {name}. {days} days in. Evenings still pull sometimes. That's a pattern, not a prophecy.",
    tods: {'evening'},
    bands: _long,
  ),
  _M(
    'g23',
    _g,
    "Hey {name}. Hour {hours}. You're early, and that's okay. Get set up for the next day.",
    bands: _early,
    tods: {'afternoon', 'evening'},
  ),
  _M(
    'g24',
    _g,
    "Hi {name}. You opened the app, so part of you is still fighting for this. Let's back that part up.",
  ),
  _M(
    'g25',
    _g,
    "Night, {name}. Phone light low, water close, something boring on. Let's ride the night.",
    tods: {'night'},
  ),
  _M(
    'g26',
    _g,
    "Morning, {name}. A shower and something warm to drink is a solid start.",
    tods: {'morning'},
    bands: {..._peak, ..._late},
  ),
  _M(
    'g27',
    _g,
    "Hey {name}. {days} days. Is there one thing you've started enjoying again? Even small.",
    bands: {'m1_3', 'm3plus'},
  ),
  _M(
    'g28',
    _g,
    "Afternoon, {name}. Middle of the day is a good time for a walk, even ten minutes.",
    tods: {'afternoon'},
    bands: {..._late, ..._weeks, ..._long},
  ),

  // ---------- Praise / acknowledgement ----------
  _M(
    'p01',
    _p,
    "{hours} hours. Your body has gone without it for more than a day and you didn't give in. That's real.",
    bands: {'h24_48'},
  ),
  _M(
    'p02',
    _p,
    "Past 48 hours. Most of the peak is around you or behind you now, not ahead forever.",
    bands: {'h48_72'},
  ),
  _M(
    'p03',
    _p,
    'Day {days}. You stuck it out through the worst stretch. That took something.',
    bands: _late,
  ),
  _M('p04', _p, 'You opened the app instead of going out to buy. That counts.'),
  _M(
    'p05',
    _p,
    'Thanks for checking in honestly. Knowing how you really feel is how this gets easier.',
  ),
  _M(
    'p06',
    _p,
    "After a long stretch of daily use, you've put real days between you and it. Don't skip past that.",
    bands: {..._weeks, ..._long},
  ),
  _M(
    'p07',
    _p,
    "This try is already different: you know what's coming and you've got a plan.",
  ),
  _M(
    'p08',
    _p,
    '{hours} hours. A day ago this number felt far away.',
    bands: {'h24_48', 'h48_72'},
  ),
  _M(
    'p09',
    _p,
    'Starting is the bit most people put off. You did it.',
    bands: _early,
  ),
  _M(
    'p10',
    _p,
    "{days} days. Your best run so far is {best} days. You're building on it, not starting from zero.",
    bands: {..._late, ..._weeks, ..._long},
  ),
  _M(
    'p11',
    _p,
    "Money not spent so far: {saved}. That's yours now.",
    bands: {..._late, ..._weeks, ..._long},
  ),
  _M(
    'p12',
    _p,
    "You felt the pull and you're still here. That's the skill. It gets stronger every time you use it.",
    minCraving: 1,
  ),
  _M(
    'p13',
    _p,
    "Two weeks plus. Your sleep and gut have been doing a lot of repair work. So have you.",
    bands: {'w2_4'},
  ),
  _M(
    'p14',
    _p,
    'A month or more. This is the stretch where it starts being your normal.',
    bands: {'m1_3'},
  ),
  _M(
    'p15',
    _p,
    "Three months plus. You've lived through every season of cravings so far. Respect.",
    bands: {'m3plus'},
  ),
  _M(
    'p16',
    _p,
    'Feeling okay today? Notice it. You earned this one.',
    moods: {'okay', 'good'},
  ),
  _M(
    'p17',
    _p,
    'Hard day and you still checked in. That honesty is part of why this works.',
    moods: {'low', 'anxious', 'irritable'},
  ),
  _M(
    'p18',
    _p,
    "Not every day has to feel like a win. Today you didn't use, and that's the win.",
    moods: {'low', 'numb'},
  ),
  _M(
    'p19',
    _p,
    "{hours} hours. The first stretch is where most attempts wobble, and you're through a chunk of it.",
    bands: {'h12_24'},
  ),
  _M(
    'p20',
    _p,
    'One week. That is a real number. Write down what helped most, so future you knows.',
    bands: {'d7_14'},
  ),
  _M(
    'p21',
    _p,
    "Night survived. Those count double.",
    tods: {'morning'},
    bands: {..._peak, ..._late},
  ),
  _M(
    'p22',
    _p,
    'You came back after a slip. That is the hardest move in recovery and you made it.',
    lapse: true,
  ),
  _M(
    'p23',
    _p,
    'You rode out a craving earlier. Your brain logged that: it learned the urge can pass without using.',
    minCraving: 2,
  ),
  _M(
    'p24',
    _p,
    "{days} days. The urges you've already beaten are proof you can beat this one.",
    bands: {..._weeks, ..._long},
  ),
  _M(
    'p25',
    _p,
    'Choosing comfort over the bottle, again and again. That is what recovery actually looks like.',
  ),
  _M(
    'p26',
    _p,
    'Small win check: did you drink water today? Eat something? Those count.',
    bands: {..._peak, ..._late},
  ),

  // ---------- Normalise / you're not trapped ----------
  _M(
    'n01',
    _n,
    "What you feel now is withdrawal, not who you are. It's temporary. It usually starts easing in about {easeIn} hours.",
    bands: _peak,
  ),
  _M(
    'n02',
    _n,
    'Cramps and the runs are your gut waking up. Annoying, normal, it passes. Sip something salty-sweet like ORS.',
    symptoms: {'gut'},
  ),
  _M(
    'n03',
    _n,
    'Hot one minute, cold the next. Classic for this stage. Wear layers you can peel off.',
    symptoms: {'sweats'},
  ),
  _M(
    'n04',
    _n,
    "Bad sleep now is expected, and it comes back. A few rough nights don't break you.",
    symptoms: {'sleep'},
  ),
  _M(
    'n05',
    _n,
    "The anxious buzz is chemistry, not a sign that something's wrong with you.",
    symptoms: {'anxiety'},
  ),
  _M(
    'n06',
    _n,
    'Restless legs are one of the most common symptoms. Walking, stretching or a warm shower helps.',
    symptoms: {'restless'},
  ),
  _M(
    'n07',
    _n,
    'Flat days a few weeks in are a known part of recovery. They come in waves, and for most people they get shorter.',
    symptoms: {'lowmood'},
    bands: _long,
  ),
  _M(
    'n08',
    _n,
    'Nothing feeling fun yet is your brain re-tuning. Pleasure comes back gradually. Keep doing small good things anyway.',
    moods: {'numb'},
  ),
  _M(
    'n09',
    _n,
    "You have choices right now: rest, move, eat, message someone. You're not trapped.",
  ),
  _M(
    'n10',
    _n,
    'Aches feel like a bad flu. Warm water, a heat pack and paracetamol as the label says can take the edge off.',
    symptoms: {'aches'},
  ),
  _M(
    'n11',
    _n,
    'Nausea? Small sips, not big gulps. Dry toast or a biscuit, then wait a few minutes.',
    symptoms: {'gut'},
  ),
  _M(
    'n12',
    _n,
    "Runny nose, yawning, watery eyes. Annoying but harmless, and a sign your body is resetting.",
    bands: _early,
  ),
  _M(
    'n13',
    _n,
    "Feeling low right now is a symptom too. It's not the truth about your life.",
    symptoms: {'lowmood'},
  ),
  _M(
    'n14',
    _n,
    "Irritable and snappy? That's the withdrawal talking. Give yourself, and the people around you, some slack today.",
    moods: {'irritable'},
  ),
  _M(
    'n15',
    _n,
    "Hour {hours} is usually around the worst of it. Not the rest of your life. Just this stretch.",
    bands: {'h24_48', 'h48_72'},
  ),
  _M(
    'n16',
    _n,
    "If you're shaky and sweaty and sure it'll never end: that's exactly how peak withdrawal feels. It does end.",
    bands: _peak,
    symptoms: {'sweats', 'anxiety'},
  ),
  _M(
    'n17',
    _n,
    "Brain fog is common in the first weeks. Write things down and go easy on big decisions.",
    bands: {..._late, ..._weeks},
  ),
  _M(
    'n18',
    _n,
    "Waking at 3 AM is common. Don't fight it. Lie still, breathe slow, rest still counts.",
    symptoms: {'sleep'},
    tods: {'night'},
  ),
  _M(
    'n19',
    _n,
    'Loose stools mean you lose water and salt. One glass of ORS after each trip to the toilet.',
    symptoms: {'gut'},
  ),
  _M(
    'n20',
    _n,
    "Muscle aches peak with the rest of it and fade over days. You won't feel like this in a week.",
    symptoms: {'aches'},
    bands: _peak,
  ),
  _M(
    'n21',
    _n,
    'Anxiety lies about the future. Right now, in this room, you are okay.',
    symptoms: {'anxiety'},
    moods: {'anxious'},
  ),
  _M(
    'n22',
    _n,
    'Your body is working hard. Being tired is a normal response, not laziness.',
    moods: {'numb', 'low'},
    bands: {..._late, ..._weeks},
  ),
  _M(
    'n23',
    _n,
    "If you're past the peak and still rough, that's common for someone who used daily for a long time. Slower, not stuck.",
    bands: _late,
  ),
  _M(
    'n24',
    _n,
    'Cravings can come out of nowhere even on good weeks. That is a cue, not a step back.',
    bands: _long,
  ),
  _M(
    'n25',
    _n,
    "You don't have to feel good to be doing well. Feeling rough and not using is doing well.",
    moods: {'low', 'irritable', 'anxious'},
  ),
  _M(
    'n26',
    _n,
    "Feeling everything louder than usual? Emotions come back loud after a long time numbed. It settles.",
    bands: {..._late, ..._weeks},
  ),
  _M(
    'n27',
    _n,
    "Goosebumps and chills are your nervous system recalibrating. A blanket and something warm help.",
    symptoms: {'sweats'},
  ),
  _M(
    'n28',
    _n,
    "You can't think your way out of a craving at hour {hours}. You can only wait it out, and it passes.",
    bands: _peak,
    minCraving: 2,
  ),
  _M(
    'n29',
    _n,
    'Feeling nothing is not the same as feeling worse. Numb usually comes before better.',
    moods: {'numb'},
  ),
  _M(
    'n30',
    _n,
    "Slept badly again? Keep the same wake-up time anyway. It's the fastest way sleep comes back.",
    symptoms: {'sleep'},
    tods: {'morning'},
  ),
  _M(
    'n31',
    _n,
    'Restless at night: get up, walk around the room, stretch your calves, lie back down. Repeat. No shame in it.',
    symptoms: {'restless'},
    tods: {'night'},
  ),
  _M(
    'n32',
    _n,
    'Appetite gone? Small and often wins. A few spoons of curd rice or khichdi is plenty.',
    bands: _peak,
  ),
  _M(
    'n33',
    _n,
    'Sweats soak through? Keep a spare T-shirt by the bed and swap it. Small comfort, big difference.',
    symptoms: {'sweats'},
    tods: {'night', 'evening'},
  ),
  _M(
    'n34',
    _n,
    'The mind will offer "just one, to sleep". That thought is withdrawal, not wisdom.',
    symptoms: {'sleep'},
    minCraving: 1,
  ),
  _M(
    'n35',
    _n,
    'Feeling okay? Good. Okay days are the ones that build the new normal.',
    moods: {'okay', 'good'},
  ),
  _M(
    'n36',
    _n,
    "Low mood a few weeks in doesn't mean it's not working. It's one of the most common parts of recovery.",
    moods: {'low'},
    bands: _long,
  ),
  _M(
    'n37',
    _n,
    'Stomach cramps: lie on your side with knees bent and a warm pack on your belly. Breathe into it.',
    symptoms: {'gut'},
  ),
  _M(
    'n38',
    _n,
    "If you're tense all over, tense your shoulders hard for five seconds, then drop them. Do it three times.",
    symptoms: {'anxiety', 'restless', 'aches'},
  ),

  // ---------- Together / not alone ----------
  _M(
    't01',
    _t,
    "Lots of people have been exactly here, at hour {hours}, and come out the other side. You're one of many.",
    bands: _peak,
  ),
  _M(
    't02',
    _t,
    "{contact} is one tap away. You don't need a reason. 'Rough hour' is enough.",
  ),
  _M(
    't03',
    _t,
    "Somebody who cares about you would rather get a 3 AM text than not know. You're allowed to send it.",
    tods: {'night'},
  ),
  _M(
    't04',
    _t,
    "You're not doing this alone. Your own past self left notes for you in Letters. Want to read one?",
  ),
  _M(
    't05',
    _t,
    'Your plan, your people, your reasons. All saved here, even offline.',
  ),
  _M(
    't06',
    _t,
    "No one has to know everything. But one person knowing 'today is hard' changes a lot.",
  ),
  _M(
    't07',
    _t,
    "You don't need to explain or apologise. 'Can you talk for 10 minutes?' is a full message.",
  ),
  _M(
    't08',
    _t,
    'Being alone with this is when it gets heaviest. Even a call about nothing helps.',
    moods: {'low', 'numb'},
  ),
  _M(
    't09',
    _t,
    "Message {contact}. Not about the craving, about anything. Connection works even if you never mention it.",
    minCraving: 1,
  ),
  _M(
    't10',
    _t,
    "Feeling alone? You're talking to an app a friend made for you. That's not nothing. Someone wanted you to have this.",
  ),
  _M(
    't11',
    _t,
    "Everyone who's quit for good has had nights like this. They didn't do it alone, and you don't have to.",
    tods: {'night', 'evening'},
  ),
  _M(
    't12',
    _t,
    'Recovery is easier with people who get it. If there is someone in your life who has quit something, they might be worth a call.',
    bands: {..._weeks, ..._long},
  ),
  _M(
    't13',
    _t,
    "Plans with people beat willpower. Is there someone you could see this week who doesn't use?",
    bands: {..._late, ..._weeks, ..._long},
  ),
  _M(
    't14',
    _t,
    "If talking feels like too much, send one emoji to {contact}. They'll get it.",
  ),
  _M(
    't15',
    _t,
    "You can keep this private and still not be alone. One trusted person is enough.",
  ),
  _M(
    't16',
    _t,
    'The friend who set this up for you is in your corner. That stays true on bad days.',
  ),
  _M(
    't17',
    _t,
    "Being with people who use makes it harder. It's okay to say 'not tonight' and leave.",
    bands: {..._weeks, ..._long},
  ),
  _M(
    't18',
    _t,
    'Hard stretch, so get some company. Text first, call second, see someone third. Pick one.',
    moods: {'low', 'anxious'},
  ),
  _M(
    't19',
    _t,
    "You've already told the app the truth. Telling one human is the next step, when you're ready.",
  ),
  _M(
    't20',
    _t,
    "{contact} said yes to being your person. Letting them help is part of the deal.",
    minCraving: 2,
  ),
  _M(
    't21',
    _t,
    'Feeling ashamed makes us hide. Hiding makes cravings louder. One honest message breaks that loop.',
    lapse: true,
  ),
  _M(
    't22',
    _t,
    "If you don't want to talk about it, ask someone to just sit with you or watch something together.",
  ),

  // ---------- Cravings ----------
  _M(
    'c01',
    _c,
    'Craving wave. They rise, peak and fall, usually within about 15 to 30 minutes. Start the timer and ride it with me.',
    minCraving: 1,
  ),
  _M(
    'c02',
    _c,
    "You don't have to decide forever. Just decide for the next 15 minutes.",
    minCraving: 1,
  ),
  _M(
    'c03',
    _c,
    'Play it forward: the first 10 minutes feel good, then what? Tonight? Tomorrow morning?',
    minCraving: 1,
  ),
  _M(
    'c04',
    _c,
    'Leave the room you are in. New place, the urge often drops.',
    minCraving: 1,
  ),
  _M(
    'c05',
    _c,
    'This is a big one. Message {contact} now, then do the cold-water reset.',
    minCraving: 3,
  ),
  _M(
    'c06',
    _c,
    "Name it: 'this is a craving, it'll peak and pass.' Naming it puts a bit of space between you and it.",
    minCraving: 1,
  ),
  _M(
    'c07',
    _c,
    'Cold water on your face for 30 seconds. It slows your heart rate and cuts the urge for a moment.',
    minCraving: 2,
  ),
  _M(
    'c08',
    _c,
    "Rate it 0 to 10 right now. Then again in 10 minutes. You'll likely see the number drop.",
    minCraving: 1,
  ),
  _M(
    'c09',
    _c,
    'Eat something. Hunger and cravings feel almost the same in the body.',
    minCraving: 1,
  ),
  _M(
    'c10',
    _c,
    "Hands busy: wash dishes, fold clothes, play a game. Hard to crave while your hands are busy.",
    minCraving: 1,
  ),
  _M(
    'c11',
    _c,
    'No money on you, no route past the old spot. Make it hard to act fast.',
    minCraving: 2,
  ),
  _M(
    'c12',
    _c,
    'Your craving hour is close. Get ahead of it: snack, water, a plan for the next 30 minutes.',
    minCraving: 0,
    tods: {'evening'},
  ),
  _M(
    'c13',
    _c,
    "Urges feel urgent. That's their trick. Nothing bad happens if you wait.",
    minCraving: 2,
  ),
  _M(
    'c14',
    _c,
    "You've ridden out cravings before. Every one you ride out makes the next one weaker.",
    minCraving: 1,
    bands: {..._late, ..._weeks, ..._long},
  ),
  _M(
    'c15',
    _c,
    'Walk to the end of the street and back. Movement burns off the restless part of a craving.',
    minCraving: 1,
    tods: {'morning', 'afternoon', 'evening'},
  ),
  _M(
    'c16',
    _c,
    "Breathe out longer than you breathe in. In for 4, out for 6. Ten rounds.",
    minCraving: 1,
  ),
  _M(
    'c17',
    _c,
    'Read your reasons. The ones you wrote on a clear day.',
    minCraving: 2,
  ),
  _M(
    'c18',
    _c,
    "The voice that says 'you deserve it' is the habit, not you. You deserve sleep and a clear head tomorrow.",
    minCraving: 2,
  ),
  _M(
    'c19',
    _c,
    "Strong craving at hour {hours} is normal. It's your body asking for what it got used to. Ask it to wait.",
    minCraving: 2,
    bands: _peak,
  ),
  _M(
    'c20',
    _c,
    'Overwhelming? Get around other people right now. Living room, a shop, a friend. Cravings hate company.',
    minCraving: 3,
  ),
  _M(
    'c21',
    _c,
    'Delay deal: 15 more minutes, then decide. Then do it again.',
    minCraving: 2,
  ),
  _M(
    'c22',
    _c,
    "Hold ice cubes or a cold can. The sharp feeling pulls attention away from the urge.",
    minCraving: 2,
  ),
  _M(
    'c23',
    _c,
    "Stress is the usual trigger. What's the stress under this craving? Sometimes naming it is enough.",
    minCraving: 1,
    bands: _long,
  ),
  _M(
    'c24',
    _c,
    'Put on one song you love, loud, headphones on. Ride the song, then check the craving.',
    minCraving: 1,
  ),
  _M(
    'c25',
    _c,
    "Cravings late at night are the worst. Lie down, lights low, timer on. You don't have to win, just wait.",
    minCraving: 1,
    tods: {'night'},
  ),
  _M(
    'c26',
    _c,
    'This wave will pass whether you use or not. If you wait, you keep your progress too.',
    minCraving: 2,
  ),
  _M(
    'c27',
    _c,
    'Text {contact}: "Craving bad, just keep me company 15 min." That is enough.',
    minCraving: 2,
  ),
  _M(
    'c28',
    _c,
    'Picture the morning after using. Then picture the morning after not using. Which one do you want?',
    minCraving: 1,
  ),
  _M(
    'c29',
    _c,
    'A hot shower can reset a craving the same way it eases aches. Five minutes.',
    minCraving: 1,
    bands: _peak,
  ),
  _M(
    'c30',
    _c,
    "Bored? Boredom feeds cravings. Pick any five-minute card below, even a silly one.",
    minCraving: 1,
    moods: {'numb'},
  ),

  // ---------- Lapse / slip (zero shame) ----------
  _M(
    'l01',
    _l,
    "You used. That's information, not a verdict. What matters most is the next hour.",
    lapse: true,
  ),
  _M(
    'l02',
    _l,
    "A slip doesn't erase {best} days. Your body still kept a lot of those gains.",
    lapse: true,
  ),
  _M(
    'l03',
    _l,
    'Be careful: after a break your tolerance is lower. The old amount can be too much now. Never use alone.',
    lapse: true,
  ),
  _M(
    'l04',
    _l,
    "What happened just before? Naming the trigger is how next time goes differently.",
    lapse: true,
  ),
  _M(
    'l05',
    _l,
    "Most people who quit for good tried more than once. You're still in this.",
    lapse: true,
  ),
  _M(
    'l06',
    _l,
    "Talk to yourself the way you'd talk to a friend right now.",
    lapse: true,
  ),
  _M(
    'l07',
    _l,
    "The 'I already blew it, might as well keep going' thought is the real danger. One slip is not a relapse unless you let it be.",
    lapse: true,
  ),
  _M(
    'l08',
    _l,
    "You came back to the app. That's the comeback, right there.",
    lapse: true,
  ),
  _M(
    'l09',
    _l,
    "No reset to zero in here. Your total clean days still count.",
    lapse: true,
  ),
  _M(
    'l10',
    _l,
    'Get rid of anything left over now, while you can. Future you will thank you.',
    lapse: true,
  ),
  _M(
    'l11',
    _l,
    'Drink water, eat something, sleep if you can. Tomorrow is a normal day one, not a punishment.',
    lapse: true,
  ),
  _M(
    'l12',
    _l,
    'Guilt is heavy. Use it as fuel for a plan, not as a reason to hide.',
    lapse: true,
  ),
  _M(
    'l13',
    _l,
    "What would you tell {contact} if they slipped? Say that to yourself.",
    lapse: true,
  ),
  _M(
    'l14',
    _l,
    'One if-then plan for next time. "If the evening gets bad, then I will..." Write it in the slip notes.',
    lapse: true,
  ),
  _M(
    'l15',
    _l,
    "Slips teach you where the tricky spot is. Now you know it. That's useful.",
    lapse: true,
  ),
  _M(
    'l16',
    _l,
    "Restarting after a slip is lighter than restarting after a year. You're already ahead.",
    lapse: true,
  ),
  _M(
    'l17',
    _l,
    'If you mixed it with pills or alcohol, stay with someone tonight and do not take more.',
    lapse: true,
  ),
  _M(
    'l18',
    _l,
    "You're allowed to be disappointed. You're not allowed to give up on yourself.",
    lapse: true,
  ),
  _M(
    'l19',
    _l,
    'The next hour, not the whole week. What do you need in the next hour?',
    lapse: true,
  ),
  _M(
    'l20',
    _l,
    'Recovery is a line that wobbles, not a straight line. This is a wobble.',
    lapse: true,
  ),
  _M(
    'l21',
    _l,
    "Hours {hours} again, and that's okay. You know this road now. It's shorter when you know it.",
    lapse: true,
  ),

  // ---------- Night ----------
  _M(
    'e01',
    _e,
    'Night plan: dim lights, warm drink, something boring on, lie down. Sleep is a bonus, rest is the goal.',
    tods: {'night'},
  ),
  _M(
    'e02',
    _e,
    "Thoughts racing? Dump them in a note. They'll be there in the morning, you don't have to hold them all night.",
    tods: {'night'},
  ),
  _M(
    'e03',
    _e,
    'Screens bright? Turn it down, or put on audio instead. Your eyes and brain will thank you.',
    tods: {'night'},
  ),
  _M(
    'e04',
    _e,
    'No caffeine after the afternoon. Chamomile, warm milk or plain warm water instead.',
    tods: {'evening'},
  ),
  _M(
    'e05',
    _e,
    'Feet cold? Socks. Sounds silly, helps sleep.',
    tods: {'night', 'evening'},
  ),
  _M(
    'e06',
    _e,
    "Can't sleep after 20 minutes? Get up, sit somewhere dim, come back when you're drowsy.",
    tods: {'night'},
    symptoms: {'sleep'},
  ),
  _M(
    'e07',
    _e,
    'Count breaths to 10 and start over. When you lose count, start over. It is fine to lose count.',
    tods: {'night'},
  ),
  _M(
    'e08',
    _e,
    "The night always feels longer than it is. Sunrise is coming whether you sleep or not.",
    tods: {'night'},
  ),
  _M(
    'e09',
    _e,
    'Set up tomorrow now: water by the bed, clothes out, one easy plan for the morning.',
    tods: {'evening'},
  ),
  _M(
    'e10',
    _e,
    'Evenings were the old routine. Build a new one: shower, food, a show, bed. Same order every night.',
    tods: {'evening'},
  ),
  _M(
    'e11',
    _e,
    'Lie on your back, hands on your belly, feel it rise. Five slow breaths. Again.',
    tods: {'night'},
  ),
  _M(
    'e12',
    _e,
    "If it's 4 AM and you feel the worst you've felt: that is the hour that lies the most. Hang on for the light.",
    tods: {'night'},
    bands: _peak,
  ),
  _M(
    'e13',
    _e,
    "Hungry at night? A small snack is better than lying awake. Biscuits and warm milk count.",
    tods: {'night'},
  ),
  _M(
    'e14',
    _e,
    'A podcast or audiobook you have heard before is perfect: nothing to follow, just company.',
    tods: {'night'},
  ),
  _M(
    'e15',
    _e,
    'Heat pack on the lower back or belly can make lying down bearable.',
    tods: {'night', 'evening'},
    symptoms: {'aches', 'gut'},
  ),

  // ---------- PAWS / long-term ----------
  _M(
    'w01',
    _w,
    "Day {days}: cravings can show up out of nowhere. That's not a step back, it's a cue. Ride it.",
    bands: _long,
  ),
  _M(
    'w02',
    _w,
    'Stress is the biggest trigger at this stage. One small thing to lower it today?',
    bands: _long,
  ),
  _M(
    'w03',
    _w,
    'Your sleep is still repairing. Same wake-up time every day speeds it up.',
    bands: _long,
  ),
  _M(
    'w04',
    _w,
    '{days} days. Money not spent: {saved}. What is one thing it could go towards?',
    bands: _long,
  ),
  _M(
    'w05',
    _w,
    'Good days and bad days both mean you are recovering. Bad days are just louder.',
    bands: _long,
  ),
  _M(
    'w06',
    _w,
    "If you felt clear for a while and now feel low again, that's a known pattern. It comes in waves.",
    bands: {'m1_3', 'm3plus'},
  ),
  _M(
    'w07',
    _w,
    'Brain fog and forgetfulness are common for a while. Lists and phone reminders are your friends.',
    bands: _long,
  ),
  _M(
    'w08',
    _w,
    'Small pleasant things, scheduled, even if they do not feel good yet. Feeling follows doing.',
    bands: _long,
    moods: {'numb', 'low'},
  ),
  _M(
    'w09',
    _w,
    'Exercise is one of the few things shown to cut cravings and lift mood. Ten minutes counts.',
    bands: _long,
  ),
  _M(
    'w10',
    _w,
    'Paydays and free evenings are risk times. Plan them before they arrive.',
    bands: _long,
  ),
  _M(
    'w11',
    _w,
    "Feeling 'cured' is great. Keep the plan anyway. Overconfidence is a classic trap at this stage.",
    bands: {'m1_3', 'm3plus'},
    moods: {'good'},
  ),
  _M(
    'w12',
    _w,
    'Irritable for no reason? That is common in later recovery too. It is not a personality change, it fades.',
    bands: _long,
    moods: {'irritable'},
  ),
  _M(
    'w13',
    _w,
    "Build the life that makes using pointless: people, routine, something to look forward to.",
    bands: _long,
  ),
  _M(
    'w14',
    _w,
    "Old places and old friends can set off cravings months later. That doesn't mean you're weakening, it's memory.",
    bands: {'m1_3', 'm3plus'},
  ),
  _M(
    'w15',
    _w,
    '{days} days. You are not the same person who started. Check how far you have come in Progress.',
    bands: _long,
  ),
  _M(
    'w16',
    _w,
    'If low mood is heavy and sticks around for weeks, talk to a doctor. Treating it lowers relapse risk.',
    bands: _long,
    moods: {'low'},
  ),
  _M(
    'w17',
    _w,
    'A routine sounds boring. Boring is great right now. Boring is safe.',
    bands: _long,
  ),
  _M(
    'w18',
    _w,
    'Learn something small: a recipe, a song, a game. New things help the brain build new pathways.',
    bands: _long,
  ),
  _M(
    'w19',
    _w,
    "Write a letter to future you on a good day. It'll be waiting on a hard one.",
    bands: _long,
    moods: {'okay', 'good'},
  ),
  _M(
    'w20',
    _w,
    'Ups and downs are part of the process. The downs usually get shorter and further apart.',
    bands: _long,
  ),
  _M(
    'w21',
    _w,
    'Sleep still off? No screens in bed, daylight in the morning, no naps after 3 PM.',
    bands: _long,
    symptoms: {'sleep'},
  ),
  _M(
    'w22',
    _w,
    "Week two plus. The body's mostly through it. Now it's habits and feelings. Different fight, same you.",
    bands: {'w2_4'},
  ),
  _M(
    'w23',
    _w,
    'Celebrate without the old habit: good food, a film, time with someone. You get to choose new rewards.',
    bands: _long,
    moods: {'good', 'okay'},
  ),
  _M(
    'w24',
    _w,
    "Anxious for no clear reason? Longer-term recovery can bring that. Breathing, walking and talking all help.",
    bands: _long,
    moods: {'anxious'},
  ),
  _M(
    'w25',
    _w,
    'Your old craving hour still matters. Keep something planned for it, even months in.',
    bands: {'m1_3', 'm3plus'},
  ),
];
