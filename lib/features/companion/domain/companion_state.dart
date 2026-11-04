/// Local-only companion data: substances, triggers, reach-out texts,
/// message history and slip notes. Stored in recovery state v16 under
/// `companion` and exported in backup format 11. Nothing leaves the phone.
library;

enum Substance {
  codeine('Codeine / lean'),
  benzo('Benzos (Valium, alprazolam, etc.)'),
  alcohol('Alcohol'),
  weed('Weed'),
  other('Something else');

  const Substance(this.label);
  final String label;
}

const defaultTriggerOptions = <String>[
  'Evenings',
  'Late night',
  'Bored',
  'Alone',
  'Stress',
  'Bad sleep',
  'With friends who use',
  'After an argument',
  'Payday / cash in hand',
  'Passing the old spot',
];

const defaultReachOutTexts = <String>[
  'Hey, rough hour. Can you just text with me for a bit?',
  "I'm at {hours} hours and it's hard. Can you call me?",
  'Not in danger, just need company. You free?',
  "Craving badly. Can you stay on the phone with me for 20 min?",
  "I slipped. I'm okay. I want to get back on track. Can we talk?",
];

class SlipNote {
  const SlipNote({
    required this.at,
    this.trigger = '',
    this.ifThen = '',
    this.substances = const {},
  });
  final DateTime at;
  final String trigger;
  final String ifThen;

  /// What was taken in this slip (optional, user-picked).
  final Set<Substance> substances;

  Map<String, Object> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'trigger': trigger,
    'ifThen': ifThen,
    if (substances.isNotEmpty)
      'substances': [for (final x in substances) x.name],
  };

  static SlipNote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse(raw['at']?.toString() ?? '');
    if (at == null) return null;
    return SlipNote(
      at: at,
      trigger: _str(raw['trigger'], 200),
      ifThen: _str(raw['ifThen'], 300),
      substances: {
        if (raw['substances'] is List)
          for (final n in raw['substances'] as List)
            ...Substance.values.where((x) => x.name == n),
      },
    );
  }
}

String _str(Object? v, int max) =>
    v is String ? (v.length > max ? v.substring(0, max) : v) : '';

class CompanionState {
  const CompanionState({
    this.substances = const {},
    this.heavyAlcohol = false,
    this.triggers = const [],
    this.triggersAsked = false,
    this.reachOutTexts = defaultReachOutTexts,
    this.shown = const {},
    this.helpful = const {},
    this.notHelpful = const {},
    this.slips = const [],
  });

  final Set<Substance> substances;

  /// Daily or heavy drinking: alcohol withdrawal can be dangerous.
  final bool heavyAlcohol;
  final List<String> triggers;
  final bool triggersAsked;
  final List<String> reachOutTexts;

  /// Message id -> last time shown.
  final Map<String, DateTime> shown;
  final Map<String, int> helpful;
  final Map<String, int> notHelpful;
  final List<SlipNote> slips;

  bool get needsTaperWarning =>
      substances.contains(Substance.benzo) ||
      (substances.contains(Substance.alcohol) && heavyAlcohol);

  CompanionState copyWith({
    Set<Substance>? substances,
    bool? heavyAlcohol,
    List<String>? triggers,
    bool? triggersAsked,
    List<String>? reachOutTexts,
    Map<String, DateTime>? shown,
    Map<String, int>? helpful,
    Map<String, int>? notHelpful,
    List<SlipNote>? slips,
  }) => CompanionState(
    substances: substances ?? this.substances,
    heavyAlcohol: heavyAlcohol ?? this.heavyAlcohol,
    triggers: triggers ?? this.triggers,
    triggersAsked: triggersAsked ?? this.triggersAsked,
    reachOutTexts: reachOutTexts ?? this.reachOutTexts,
    shown: shown ?? this.shown,
    helpful: helpful ?? this.helpful,
    notHelpful: notHelpful ?? this.notHelpful,
    slips: slips ?? this.slips,
  );

  /// Records that [ids] were shown; prunes entries older than 30 days.
  CompanionState markShown(Iterable<String> ids, DateTime at) {
    final cutoff = at.subtract(const Duration(days: 30));
    final next = {
      for (final e in shown.entries)
        if (e.value.isAfter(cutoff)) e.key: e.value,
    };
    for (final id in ids) {
      next[id] = at;
    }
    return copyWith(shown: next);
  }

  CompanionState rate(String id, {required bool wasHelpful}) {
    final map = Map.of(wasHelpful ? helpful : notHelpful);
    map[id] = (map[id] ?? 0) + 1;
    return wasHelpful ? copyWith(helpful: map) : copyWith(notHelpful: map);
  }

  Map<String, Object> toJson() => {
    'substances': substances.map((s) => s.name).toList(),
    'heavyAlcohol': heavyAlcohol,
    'triggers': triggers,
    'triggersAsked': triggersAsked,
    'reachOutTexts': reachOutTexts,
    'shown': {
      for (final e in shown.entries) e.key: e.value.toUtc().toIso8601String(),
    },
    'helpful': helpful,
    'notHelpful': notHelpful,
    'slips': slips.map((s) => s.toJson()).toList(),
  };

  static CompanionState fromJson(Object? raw) {
    if (raw is! Map) return const CompanionState();
    List<String> strings(Object? v, int maxLen, int maxCount) => v is List
        ? v
              .whereType<String>()
              .map((s) => _str(s, maxLen))
              .where((s) => s.trim().isNotEmpty)
              .take(maxCount)
              .toList()
        : const [];
    Map<String, int> counts(Object? v) => v is Map
        ? {
            for (final e in v.entries)
              if (e.value is int) e.key.toString(): e.value as int,
          }
        : const {};
    final texts = strings(raw['reachOutTexts'], 300, 12);
    return CompanionState(
      substances: raw['substances'] is List
          ? (raw['substances'] as List)
                .map(
                  (n) => Substance.values.where((s) => s.name == n).firstOrNull,
                )
                .whereType<Substance>()
                .toSet()
          : const {},
      heavyAlcohol: raw['heavyAlcohol'] == true,
      triggers: strings(raw['triggers'], 60, 20),
      triggersAsked: raw['triggersAsked'] == true,
      reachOutTexts: texts.isEmpty ? defaultReachOutTexts : texts,
      shown: raw['shown'] is Map
          ? {
              for (final e in (raw['shown'] as Map).entries)
                if (DateTime.tryParse(e.value.toString()) != null)
                  e.key.toString(): DateTime.parse(e.value.toString()),
            }
          : const {},
      helpful: counts(raw['helpful']),
      notHelpful: counts(raw['notHelpful']),
      slips: raw['slips'] is List
          ? (raw['slips'] as List)
                .map(SlipNote.fromJson)
                .whereType<SlipNote>()
                .take(100)
                .toList()
          : const [],
    );
  }

  /// Backup merge: local answers win once set; history and slips union.
  CompanionState mergeImported(CompanionState other) {
    final slipKeys = slips.map((s) => s.at.toUtc().toIso8601String()).toSet();
    return CompanionState(
      substances: substances.isEmpty ? other.substances : substances,
      heavyAlcohol: heavyAlcohol || other.heavyAlcohol,
      triggers: triggersAsked ? triggers : other.triggers,
      triggersAsked: triggersAsked || other.triggersAsked,
      reachOutTexts: reachOutTexts,
      shown: {...other.shown, ...shown},
      helpful: {...other.helpful, ...helpful},
      notHelpful: {...other.notHelpful, ...notHelpful},
      slips: [
        ...slips,
        ...other.slips.where(
          (s) => slipKeys.add(s.at.toUtc().toIso8601String()),
        ),
      ]..sort((a, b) => b.at.compareTo(a.at)),
    );
  }
}
