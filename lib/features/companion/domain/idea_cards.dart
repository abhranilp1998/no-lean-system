/// Five-minute "right now" actions. Offline, bundled.
library;

enum IdeaCategory { body, calm, craving, distract, reach }

class IdeaCard {
  const IdeaCard(
    this.id,
    this.category,
    this.title,
    this.steps, {
    this.minutes = 5,
    this.symptoms = const {},
    this.tods = const {},
    this.minCraving = 0,
    this.action,
  });
  final String id;
  final IdeaCategory category;
  final String title;
  final List<String> steps;
  final int minutes;
  final Set<String> symptoms;
  final Set<String> tods;
  final int minCraving;

  /// Optional in-app action: 'surf', 'reach', 'letters', 'sos'.
  final String? action;
}

const ideaCards = <IdeaCard>[
  IdeaCard(
    'i01',
    IdeaCategory.body,
    'Sip break',
    [
      'Make a glass of ORS, or water with a pinch of salt and sugar.',
      'Sip slowly over 5 minutes.',
      'Repeat after every loose stool.',
    ],
    symptoms: {'gut', 'sweats'},
  ),
  IdeaCard(
    'i02',
    IdeaCategory.body,
    'Warm shower',
    [
      '5 minutes of warm, not hot, water.',
      'Let it run on the spots that ache most.',
      'Dry off and put on fresh, loose clothes.',
    ],
    symptoms: {'aches', 'sweats', 'restless'},
  ),
  IdeaCard(
    'i03',
    IdeaCategory.body,
    'Heat pack',
    [
      'Hot water bottle or a warm towel.',
      'On your belly for cramps, lower back for aches.',
      'Lie on your side, knees bent.',
    ],
    symptoms: {'gut', 'aches'},
  ),
  IdeaCard(
    'i04',
    IdeaCategory.body,
    'Bland snack',
    [
      'Banana, toast, curd rice or khichdi.',
      'A few bites is enough.',
      'Wait 10 minutes before more.',
    ],
    symptoms: {'gut'},
  ),
  IdeaCard(
    'i05',
    IdeaCategory.body,
    'Layer swap',
    [
      'Swap a sweaty shirt for a dry one.',
      'Keep a light blanket you can throw off.',
    ],
    minutes: 2,
    symptoms: {'sweats'},
  ),
  IdeaCard(
    'i06',
    IdeaCategory.body,
    'Leg stretch',
    [
      'Calf stretch against a wall, 1 minute each leg.',
      'Hamstring stretch, 1 minute each leg.',
      'Walk slowly around the room.',
    ],
    symptoms: {'restless', 'aches'},
  ),
  IdeaCard(
    'i07',
    IdeaCategory.calm,
    'Box breathing',
    [
      'Breathe in for 4.',
      'Hold for 4.',
      'Out for 4, hold for 4.',
      'Six rounds.',
    ],
    minutes: 2,
    symptoms: {'anxiety'},
  ),
  IdeaCard(
    'i08',
    IdeaCategory.calm,
    'Cold-water reset',
    [
      'Splash cold water on your face, or hold ice for 30 seconds.',
      'Breathe out slowly while you do it.',
    ],
    minutes: 1,
    symptoms: {'anxiety'},
    minCraving: 2,
  ),
  IdeaCard(
    'i09',
    IdeaCategory.calm,
    '5-4-3-2-1',
    [
      'Name 5 things you can see.',
      '4 you can touch, 3 you can hear.',
      '2 you can smell, 1 you can taste.',
    ],
    minutes: 3,
    symptoms: {'anxiety'},
  ),
  IdeaCard(
    'i10',
    IdeaCategory.calm,
    'Body scan',
    [
      'Lie down, eyes closed.',
      'Move attention from toes to head, slowly.',
      "Where it hurts, breathe there. Don't fight it.",
    ],
    symptoms: {'aches', 'sleep'},
  ),
  IdeaCard(
    'i11',
    IdeaCategory.craving,
    'Ride the wave',
    [
      'Start the 20-minute urge timer.',
      'Rate the craving at the start and the end.',
      'Watch it peak and pass.',
    ],
    minutes: 20,
    minCraving: 1,
    action: 'surf',
  ),
  IdeaCard('i12', IdeaCategory.craving, 'Delay deal', [
    'Tell yourself: 15 more minutes, then I decide.',
    'Do any other card in the meantime.',
    'Then make the same deal again.',
  ], minCraving: 1),
  IdeaCard(
    'i13',
    IdeaCategory.craving,
    'Play the tape forward',
    [
      'Picture using: the first 10 minutes.',
      'Now the next morning, the money, the reset.',
      'Now picture tomorrow if you wait.',
    ],
    minutes: 3,
    minCraving: 1,
  ),
  IdeaCard(
    'i14',
    IdeaCategory.craving,
    'Change rooms',
    [
      'Get up and go somewhere else: another room, outside, a shop.',
      'Somewhere with people is even better.',
    ],
    minutes: 3,
    minCraving: 1,
  ),
  IdeaCard(
    'i15',
    IdeaCategory.craving,
    'Read a letter to yourself',
    ['Open Letters.', 'Read the one you wrote on a good day.'],
    minutes: 3,
    minCraving: 1,
    action: 'letters',
  ),
  IdeaCard('i16', IdeaCategory.distract, 'One easy episode', [
    'Something you have seen before.',
    'Snacks and water within reach.',
  ], minutes: 20),
  IdeaCard('i17', IdeaCategory.distract, 'Tidy one thing', [
    'One drawer, one shelf, or the dishes.',
    'Stop after 5 minutes, even if not done.',
  ]),
  IdeaCard(
    'i18',
    IdeaCategory.distract,
    'Three lines',
    [
      'Write three lines about how you feel.',
      "No one reads it. It doesn't have to be good.",
    ],
    minutes: 3,
    symptoms: {'lowmood', 'anxiety'},
  ),
  IdeaCard(
    'i19',
    IdeaCategory.distract,
    'Music, loud',
    ['Headphones on.', 'Three songs you love.', 'Check how you feel after.'],
    minutes: 10,
    symptoms: {'lowmood'},
  ),
  IdeaCard(
    'i20',
    IdeaCategory.reach,
    'Message your person',
    ['Pick a ready message, edit it if you like.', 'Send it. Short is fine.'],
    minutes: 1,
    action: 'reach',
  ),
  IdeaCard(
    'i21',
    IdeaCategory.body,
    'Short walk',
    ['10 minutes outside, any pace.', 'Leave cash and cards at home.'],
    minutes: 10,
    symptoms: {'restless', 'lowmood'},
    tods: {'morning', 'afternoon', 'evening'},
  ),
  IdeaCard(
    'i22',
    IdeaCategory.calm,
    'Rest without sleep',
    [
      'Lie down, lights low.',
      'Tell yourself: rest is enough.',
      'Breathe out longer than in.',
    ],
    minutes: 10,
    symptoms: {'sleep'},
    tods: {'night'},
  ),
];
