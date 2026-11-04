import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device notes meant for the developer. Nothing leaves the phone until
/// the user exports them.
class FeedbackNote {
  const FeedbackNote({required this.at, required this.text});
  final DateTime at;
  final String text;

  Map<String, Object> toJson() => {'at': at.toIso8601String(), 'text': text};

  static FeedbackNote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at']}');
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
      FeedbackNote(at: DateTime.now(), text: trimmed),
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

final feedbackStoreProvider = Provider((_) => FeedbackStore());
