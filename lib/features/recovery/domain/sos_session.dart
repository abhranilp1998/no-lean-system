class SosSession {
  const SosSession({required this.startedAt, this.completedAt});

  final DateTime startedAt;
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  Duration? get duration {
    final end = completedAt;
    if (end == null || end.isBefore(startedAt)) return null;
    return end.difference(startedAt);
  }

  SosSession complete([DateTime? at]) {
    final completion = at ?? DateTime.now();
    return SosSession(
      startedAt: startedAt,
      completedAt: completion.isBefore(startedAt) ? startedAt : completion,
    );
  }

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory SosSession.fromJson(Map<String, dynamic> json) {
    final startedAt =
        DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
        DateTime.now();
    final completedAt = DateTime.tryParse(
      json['completedAt']?.toString() ?? '',
    );

    return SosSession(
      startedAt: startedAt,
      completedAt: completedAt == null || completedAt.isBefore(startedAt)
          ? null
          : completedAt,
    );
  }
}
