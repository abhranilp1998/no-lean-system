import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device notes meant for the developer. Nothing leaves the phone until
/// the user exports them.
class FeedbackNote {
  const FeedbackNote({required this.at, required this.text});
  final DateTime at;
  final String text;

  /// Stored as UTC ISO-8601 (trailing Z).
  Map<String, Object> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'text': text,
  };

  static FeedbackNote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at']}')?.toUtc();
    final text = raw['text'];
    if (at == null || text is! String || text.trim().isEmpty) return null;
    return FeedbackNote(at: at, text: text);
  }
}

class FeedbackStore {
  static const key = 'feedback_notes_v1';
  static const maxNotes = 200;

  Future<List<FeedbackNote>> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final list = jsonDecode(prefs.getString(key) ?? '[]');
      if (list is! List) return [];
      return list.map(FeedbackNote.fromJson).whereType<FeedbackNote>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final all = [
      ...await load(),
      FeedbackNote(at: DateTime.now().toUtc(), text: trimmed),
    ];
    final kept = all.length > maxNotes
        ? all.sublist(all.length - maxNotes)
        : all;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(kept.map((n) => n.toJson()).toList()),
    );
  }
}

/// Plain-text bundle for AP. Only the user's own words and timestamps; no
/// recovery history, doses or contacts.
String formatFeedbackExport(List<FeedbackNote> notes, {DateTime? now}) {
  final b = StringBuffer()
    ..writeln('NO LEAN feedback for AP')
    ..writeln('Exported ${(now ?? DateTime.now()).toIso8601String()}')
    ..writeln('${notes.length} note${notes.length == 1 ? '' : 's'}')
    ..writeln();
  for (final n in notes) {
    b.writeln('- [${n.at.toIso8601String()}] ${n.text.replaceAll('\n', ' ')}');
  }
  return b.toString();
}

typedef FeedbackSharer = Future<void> Function(String text, String subject);

Future<void> _shareWithPlus(String text, String subject) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}

/// Opens the share sheet so the user chooses how it reaches AP. Returns
/// false when there is nothing to send.
Future<bool> exportFeedbackToAp(
  FeedbackStore store, {
  FeedbackSharer share = _shareWithPlus,
}) async {
  final notes = await store.load();
  if (notes.isEmpty) return false;
  await share(formatFeedbackExport(notes), 'NO LEAN feedback for AP');
  return true;
}

final feedbackStoreProvider = Provider((_) => FeedbackStore());
final feedbackSharerProvider = Provider<FeedbackSharer>((_) => _shareWithPlus);
