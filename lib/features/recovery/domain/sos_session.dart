class SosSession {
  const SosSession({
    this.id,
    required this.startedAt,
    this.completedAt,
    this.debrief,
  });

  final String? id;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? debrief;

  bool get isCompleted => completedAt != null;

  Duration? get duration {
    final end = completedAt;
    if (end == null || end.isBefore(startedAt)) return null;
    return end.difference(startedAt);
  }

  SosSession complete([DateTime? at, String? debrief]) {
    final completion = at ?? DateTime.now();
    return SosSession(
      id: id,
      startedAt: startedAt,
      completedAt: completion.isBefore(startedAt) ? startedAt : completion,
      debrief: debrief ?? this.debrief,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    if (debrief != null) 'debrief': debrief,
  };

  factory SosSession.fromJson(Map<String, dynamic> json) {
    final startedAt =
        DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
        DateTime.now();
    final completedAt = DateTime.tryParse(
      json['completedAt']?.toString() ?? '',
    );

    return SosSession(
      id: json['id'] as String?,
      startedAt: startedAt,
      completedAt: completedAt == null || completedAt.isBefore(startedAt)
          ? null
          : completedAt,
      debrief: json['debrief'] as String?,
    );
  }
}
