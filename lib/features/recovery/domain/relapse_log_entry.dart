import 'dose_units.dart';

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
    this.dose,
    this.doseParsedFromText = false,
    this.stress,
    this.cost,
  });

  static const minimumNoteLength = 12;

  final DateTime occurredAt;
  final RelapseType type;
  final String note;
  final bool attemptedSos;
  final String? quantity;
  final List<String> contextTags;

  /// Structured dose, when the user entered one. Free-text [quantity] is
  /// kept alongside it.
  final DoseAmount? dose;

  /// True when [dose] was read from the free-text [quantity] rather than
  /// entered in the amount field.
  final bool doseParsedFromText;

  /// Optional 1-5 stress rating.
  final int? stress;

  /// Optional real ₹ cost of this dose.
  final double? cost;

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
    if (stress != null && (stress! < 1 || stress! > 5)) {
      throw ArgumentError('Stress must be between 1 and 5.');
    }
    if (cost != null &&
        (!cost!.isFinite || cost! < 0 || cost! > maxRelapseCost)) {
      throw ArgumentError('Cost must be 0 or more.');
    }
  }

  Map<String, dynamic> toMetadata() => {
    'relapseType': type.name,
    'note': normalizedNote,
    'attemptedSos': attemptedSos,
    'quantity': ?normalizedQuantity,
    'contextTags': ?storedContextTags,
    'stress': ?stress,
    'cost': ?cost,
    ...?dose?.toMetadata(),
    if (dose != null && doseParsedFromText) 'amountSource': 'parsed',
  };
}
