class CravingEntry {
  CravingEntry({
    required this.intensity,
    required this.trigger,
    required this.note,
    required this.createdAt,
  });

  final int intensity;
  final String trigger;
  final String note;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'intensity': intensity,
    'trigger': trigger,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CravingEntry.fromJson(Map<String, dynamic> json) => CravingEntry(
    intensity: json['intensity'] as int? ?? 5,
    trigger: json['trigger'] as String? ?? 'Other',
    note: json['note'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}
