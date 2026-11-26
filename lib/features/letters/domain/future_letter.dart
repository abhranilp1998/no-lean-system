import 'package:uuid/uuid.dart';

import '../../notes/domain/note_crypto.dart';
import '../../recovery/domain/risk_window.dart';

/// A voice note's recording. The audio itself lives in a file named after the
/// note's id (see `VoiceNoteStore`); this is only what the note knows about it.
class VoiceClip {
  const VoiceClip({required this.durationMs, this.keyId, this.wrap});

  /// Longest recording kept.
  static const maxDuration = Duration(seconds: 60);

  final int durationMs;

  /// Set when the file is encrypted (a PIN was set): which key opens it, and
  /// the PIN-wrapped copy of that key.
  final String? keyId;
  final NoteKeyWrap? wrap;

  bool get isEncrypted => keyId != null;

  VoiceClip copyWith({
    String? keyId,
    NoteKeyWrap? wrap,
    bool clearKey = false,
  }) => VoiceClip(
    durationMs: durationMs,
    keyId: clearKey ? null : keyId ?? this.keyId,
    wrap: clearKey ? null : wrap ?? this.wrap,
  );

  Map<String, dynamic> toJson() => {
    'ms': durationMs,
    'kid': ?keyId,
    if (keyId != null && wrap != null) 'w': wrap!.toJson(),
  };

  static VoiceClip? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final ms = json['ms'];
    if (ms is! num || ms < 0) return null;
    final kid = json['kid'];
    return VoiceClip(
      durationMs: ms.round(),
      keyId: kid is String && kid.isNotEmpty ? kid : null,
      wrap: NoteKeyWrap.tryFromJson(json['w']),
    );
  }
}

/// A note the user writes to their future self: text, or a short voice note.
/// Stored in app state (v14+) and in backups (format 9+). Never sent to the
/// home-screen widget.
///
/// Optional fields only, so every older save and backup still reads:
/// * `sealed` - the text, encrypted (only while a PIN is set). [text] then
///   holds a placeholder, which is also what an older build would show.
/// * `audio` - a voice note. [text] holds a short label for the same reason.
class FutureLetter {
  const FutureLetter({
    required this.id,
    required this.text,
    required this.createdAt,
    this.sealed,
    this.audio,
  });

  factory FutureLetter.create(String text, {DateTime? at}) => FutureLetter(
    id: const Uuid().v4(),
    text: validateText(text),
    createdAt: at ?? DateTime.now(),
  );

  static const maxLetters = 100;
  static const maxLength = 4000;

  /// What [text] holds when the real text is sealed.
  static const sealedPlaceholder = 'Sealed note. Open NO LEAN to read it.';
  static const voicePlaceholder = 'Voice note to yourself.';

  final String id;
  final String text;
  final DateTime createdAt;
  final SealedPayload? sealed;
  final VoiceClip? audio;

  bool get isVoice => audio != null;
  bool get isSealed => sealed != null;

  FutureLetter copyWith({
    String? text,
    SealedPayload? sealed,
    VoiceClip? audio,
    bool clearSealed = false,
  }) => FutureLetter(
    id: id,
    text: text ?? this.text,
    createdAt: createdAt,
    sealed: clearSealed ? null : sealed ?? this.sealed,
    audio: audio ?? this.audio,
  );

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
    if (sealed != null) 'sealed': sealed!.toJson(),
    if (audio != null) 'audio': audio!.toJson(),
  };

  factory FutureLetter.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('A note must be an object.');
    final id = json['id'];
    final text = json['text'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (id is! String || id.isEmpty || text is! String || createdAt == null) {
      throw const FormatException('A note is missing required fields.');
    }
    return FutureLetter(
      id: id,
      text: validateText(text),
      createdAt: createdAt,
      sealed: SealedPayload.tryFromJson(json['sealed']),
      audio: VoiceClip.tryFromJson(json['audio']),
    );
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
