import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// (C) Feedback notes ride along in backup v12 as their raw prefs list
/// (`feedback_notes_v1`: `[{at: UTC ISO, text}]`), so this file does not
/// depend on the Tell feature. Merged by (at, text) on import; max 200.
const feedbackNotesPrefKey = 'feedback_notes_v1';
const _maxFeedbackNotes = 200;

List<Map<String, String>> _clean(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final n in raw)
      if (n is Map &&
          n['text'] is String &&
          (n['text'] as String).trim().isNotEmpty &&
          DateTime.tryParse('${n['at']}') != null)
        {
          'at': DateTime.parse('${n['at']}').toUtc().toIso8601String(),
          'text': (n['text'] as String).trim(),
        },
  ];
}

Future<List<Map<String, String>>?> exportFeedbackNotes() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final notes = _clean(
      jsonDecode(prefs.getString(feedbackNotesPrefKey) ?? '[]'),
    );
    return notes.isEmpty ? null : notes;
  } catch (_) {
    return null;
  }
}

Future<void> importFeedbackNotes(Object? raw) async {
  final incoming = _clean(raw);
  if (incoming.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  List<Map<String, String>> existing;
  try {
    existing = _clean(
      jsonDecode(prefs.getString(feedbackNotesPrefKey) ?? '[]'),
    );
  } catch (_) {
    existing = [];
  }
  final seen = existing.map((n) => '${n['at']}|${n['text']}').toSet();
  final merged = [
    ...existing,
    ...incoming.where((n) => seen.add('${n['at']}|${n['text']}')),
  ]..sort((a, b) => a['at']!.compareTo(b['at']!));
  final kept = merged.length > _maxFeedbackNotes
      ? merged.sublist(merged.length - _maxFeedbackNotes)
      : merged;
  await prefs.setString(feedbackNotesPrefKey, jsonEncode(kept));
}
