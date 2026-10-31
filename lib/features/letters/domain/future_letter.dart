import 'package:uuid/uuid.dart';

import '../../recovery/domain/risk_window.dart';

/// A note the user writes to their future self. Stored in app state (v14+)
/// and in backups (format 9+). Never sent to the home-screen widget.
class FutureLetter {
  const FutureLetter({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  factory FutureLetter.create(String text, {DateTime? at}) => FutureLetter(
    id: const Uuid().v4(),
    text: validateText(text),
    createdAt: at ?? DateTime.now(),
  );

  static const maxLetters = 100;
  static const maxLength = 4000;

  final String id;
  final String text;
  final DateTime createdAt;

  static String validateText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw const FormatException('A note cannot be empty.');
    if (trimmed.length > maxLength) {
      throw const FormatException('A note can be at most 4000 characters.');
    }
    return trimmed;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  factory FutureLetter.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('A note must be an object.');
    final id = json['id'];
    final text = json['text'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (id is! String || id.isEmpty || text is! String || createdAt == null) {
      throw const FormatException('A note is missing required fields.');
    }
    return FutureLetter(id: id, text: validateText(text), createdAt: createdAt);
  }

  /// Missing means none (older states and backups). Duplicates keep the first.
  static List<FutureLetter> decodeList(Object? json) {
    if (json == null) return const [];
    if (json is! List) throw const FormatException('Notes must be a list.');
    if (json.length > maxLetters) {
      throw const FormatException('Too many notes (at most 100).');
    }
    final seen = <String>{};
    return [
      for (final item in json.map(FutureLetter.fromJson))
        if (seen.add(item.id)) item,
    ];
  }
}

/// The evening a moment belongs to: the date of the most recent window start
/// at or before [now]. One note unlocks per evening.
DateTime eveningOf(DateTime now, RiskWindow window) {
  final startToday = DateTime(
    now.year,
    now.month,
    now.day,
    window.startMinutes ~/ 60,
    window.startMinutes % 60,
  );
  final start = now.isBefore(startToday)
      ? DateTime(now.year, now.month, now.day - 1)
      : DateTime(now.year, now.month, now.day);
  return start;
}

/// Index of tonight's note: rotates by one each evening, oldest first.
int tonightLetterIndex(int count, DateTime now, RiskWindow window) {
  if (count <= 0) return -1;
  final evening = eveningOf(now, window);
  final day = DateTime.utc(
    evening.year,
    evening.month,
    evening.day,
  ).difference(DateTime.utc(2020)).inDays;
  return day % count;
}
