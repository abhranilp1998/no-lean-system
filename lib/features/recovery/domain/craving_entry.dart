const recoveryTriggerOptions = <String>[
  'After Work',
  'Boredom',
  'Muscle Tension',
  'Loneliness',
  'Office Stress',
  'Habit',
  'Other',
];

class CravingEntry {
  CravingEntry({
    required this.intensity,
    required this.trigger,
    required this.note,
    required this.createdAt,
    this.stress,
    this.id,
  });

  final int intensity;
  final String trigger;
  final String note;
  final DateTime createdAt;

  /// Optional 1-5 stress rating at the time of the craving.
  final int? stress;

  /// Event id once recorded (null for a draft).
  final String? id;

  Map<String, dynamic> toJson() => {
    'intensity': intensity,
    'trigger': trigger,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'stress': ?stress,
  };

  factory CravingEntry.fromJson(Map<String, dynamic> json) => CravingEntry(
    intensity: json['intensity'] as int? ?? 5,
    trigger: json['trigger'] as String? ?? 'Other',
    note: json['note'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    stress: (json['stress'] as num?)?.round(),
  );
}
