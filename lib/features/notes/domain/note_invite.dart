import '../../letters/domain/future_letter.dart';

/// The good moments we may gently suggest leaving a note in.
enum NoteInviteOccasion {
  milestone,
  urgePassed,
  cleanCheckIn;

  String get headline => switch (this) {
    NoteInviteOccasion.milestone => 'A GOOD DAY TO LEAVE A NOTE',
    NoteInviteOccasion.urgePassed => 'YOU RODE IT OUT',
    NoteInviteOccasion.cleanCheckIn => 'A CLEAN DAY IS A GOOD DAY TO WRITE',
  };

  String get line => switch (this) {
    NoteInviteOccasion.milestone =>
      'A harder day will come. Tell that you something now: a few words, '
          'or your voice.',
    NoteInviteOccasion.urgePassed =>
      'You know how this felt and how it ended. Leave a few words for the '
          'next time it rises.',
    NoteInviteOccasion.cleanCheckIn =>
      'The you of a rough evening will be glad you wrote. Short is fine.',
  };
}

/// What the app remembers about invitations. Device-local, not in backups:
/// it is only about not nagging.
class NoteInviteState {
  const NoteInviteState({
    this.lastShownAt,
    this.snoozedUntil,
    this.never = false,
  });

  final DateTime? lastShownAt;
  final DateTime? snoozedUntil;

  /// "Don't suggest this again". Notes can still be added from the Notes
  /// screen any time.
  final bool never;

  Map<String, dynamic> toJson() => {
    'last': ?lastShownAt?.toIso8601String(),
    'snooze': ?snoozedUntil?.toIso8601String(),
    'never': never,
  };

  static NoteInviteState fromJson(Object? json) {
    if (json is! Map) return const NoteInviteState();
    return NoteInviteState(
      lastShownAt: DateTime.tryParse('${json['last'] ?? ''}'),
      snoozedUntil: DateTime.tryParse('${json['snooze'] ?? ''}'),
      never: json['never'] == true,
    );
  }

  NoteInviteState copyWith({
    DateTime? lastShownAt,
    DateTime? snoozedUntil,
    bool? never,
  }) => NoteInviteState(
    lastShownAt: lastShownAt ?? this.lastShownAt,
    snoozedUntil: snoozedUntil ?? this.snoozedUntil,
    never: never ?? this.never,
  );
}

/// Quiet by design: with few notes, at most once every 2 days; with a few
/// notes saved, about every two weeks; never when snoozed, switched off, or
/// full. Always optional, never blocks anything.
bool shouldInviteNote({
  required NoteInviteState state,
  required DateTime now,
  required int noteCount,
}) {
  if (state.never || noteCount >= FutureLetter.maxLetters) return false;
  final snoozed = state.snoozedUntil;
  if (snoozed != null && now.isBefore(snoozed)) return false;
  final last = state.lastShownAt;
  if (last == null) return true;
  final gap = noteCount < 3
      ? const Duration(days: 2)
      : const Duration(days: 14);
  return now.difference(last) >= gap;
}

/// A note to play at a hard moment: the next one that can be opened. Locked
/// notes are skipped. [step] cycles ("ANOTHER"); [seed] varies the start.
FutureLetter? pickNoteToPlay(
  List<FutureLetter> letters, {
  required Set<String> locked,
  required int seed,
  int step = 0,
}) {
  final open = [
    for (final l in letters)
      if (!locked.contains(l.id)) l,
  ];
  if (open.isEmpty) return null;
  return open[(seed.abs() + step) % open.length];
}
