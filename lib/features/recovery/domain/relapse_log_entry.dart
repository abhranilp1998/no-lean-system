enum RelapseType { fullLean, partial, alcohol, benzo, leanPlusAlcohol, other }

extension RelapseTypeLabel on RelapseType {
  String get label => switch (this) {
    RelapseType.fullLean => 'FULL LEAN',
    RelapseType.partial => 'PARTIAL / SIP',
    RelapseType.alcohol => 'ALCOHOL',
    RelapseType.benzo => 'BENZO',
    RelapseType.leanPlusAlcohol => 'LEAN + ALCOHOL',
    RelapseType.other => 'OTHER',
  };

  static RelapseType? fromName(Object? value) {
    if (value is! String) return null;
    return RelapseType.values.where((type) => type.name == value).firstOrNull;
  }
}

/// User-supplied facts for one newly recorded relapse.
///
/// RecoveryEvent remains the persisted source of truth. This value object only
/// validates richer input before it is written as additive event metadata.
class RelapseLogEntry {
  const RelapseLogEntry({
    required this.occurredAt,
    required this.type,
    required this.note,
    required this.attemptedSos,
    this.quantity,
    this.contextTags = const [],
  });

  static const minimumNoteLength = 12;

  final DateTime occurredAt;
  final RelapseType type;
  final String note;
  final bool attemptedSos;
  final String? quantity;
  final List<String> contextTags;

  String get normalizedNote => note.trim();

  String? get normalizedQuantity {
    final value = quantity?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  List<String> get normalizedContextTags => contextTags
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false);

  List<String>? get storedContextTags {
    final values = normalizedContextTags;
    return values.isEmpty ? null : values;
  }

  void validate({DateTime? now}) {
    final current = now ?? DateTime.now();
    if (occurredAt.isBefore(DateTime(2000)) || occurredAt.isAfter(current)) {
      throw ArgumentError('Relapse dates must be between 2000 and now.');
    }
    if (normalizedNote.length < minimumNoteLength) {
      throw ArgumentError(
        'Describe what happened in at least $minimumNoteLength characters.',
      );
    }
    if ((normalizedQuantity?.length ?? 0) > 120) {
      throw ArgumentError('Quantity must be 120 characters or fewer.');
    }
    if (normalizedContextTags.length > 10 ||
        normalizedContextTags.any((tag) => tag.length > 40)) {
      throw ArgumentError('Choose up to 10 short context signals.');
    }
  }

  Map<String, dynamic> toMetadata() => {
    'relapseType': type.name,
    'note': normalizedNote,
    'attemptedSos': attemptedSos,
    'quantity': ?normalizedQuantity,
    'contextTags': ?storedContextTags,
  };
}
