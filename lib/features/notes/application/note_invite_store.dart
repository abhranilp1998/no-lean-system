import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/note_invite.dart';

/// Remembers when we last invited. A storage failure never blocks anything:
/// it just means the app does not invite.
class NoteInviteStore {
  static const _key = 'future_note_invite_v1';

  Future<NoteInviteState> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      return raw == null
          ? const NoteInviteState()
          : NoteInviteState.fromJson(jsonDecode(raw));
    } catch (_) {
      return const NoteInviteState(never: true);
    }
  }

  Future<void> write(NoteInviteState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {
      /* Not remembering is fine. */
    }
  }

  Future<void> shown(DateTime now) async =>
      write((await read()).copyWith(lastShownAt: now));

  Future<void> snooze(DateTime now, Duration by) async => write(
    (await read()).copyWith(lastShownAt: now, snoozedUntil: now.add(by)),
  );

  Future<void> never() async => write((await read()).copyWith(never: true));
}

final noteInviteStoreProvider = Provider<NoteInviteStore>(
  (ref) => NoteInviteStore(),
);
