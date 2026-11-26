import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../letters/domain/future_letter.dart';
import '../../letters/presentation/future_letters_screen.dart';
import '../../recovery/application/recovery_provider.dart';
import '../domain/note_invite.dart';
import '../services/voice_io.dart';

/// Where a note is being played back, which sets the heading.
enum NoteMoment {
  /// During an urge (Ride the wave / urge timer).
  urge,

  /// After a slip, once the review sheet is done (and on the reset screen).
  afterSlip,

  /// On the rough-day home screen.
  roughDay;

  String get heading => switch (this) {
    NoteMoment.urge => 'FROM YOU, FOR RIGHT NOW',
    NoteMoment.afterSlip => 'YOU LEFT THIS FOR A DAY LIKE TODAY',
    NoteMoment.roughDay => 'A NOTE YOU LEFT FOR TODAY',
  };
}

/// Shows one note from the user's own future-self notes: their words, or a
/// play button for their voice. Shows nothing when there are no notes, so a
/// screen can include it unconditionally.
///
/// It reads notes without asking for the PIN again: it only appears inside
/// the already-open app, at a moment the user is in. Nothing is auto-played.
class FutureNoteCard extends ConsumerStatefulWidget {
  const FutureNoteCard({required this.moment, this.seed, super.key});

  final NoteMoment moment;

  /// Varies which note is first. Defaults to the clock.
  final int? seed;

  @override
  ConsumerState<FutureNoteCard> createState() => _FutureNoteCardState();
}

class _FutureNoteCardState extends ConsumerState<FutureNoteCard> {
  late final int _seed = widget.seed ?? DateTime.now().millisecondsSinceEpoch;
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final letters = recovery.futureLetters;
    if (letters.isEmpty) return const SizedBox.shrink();
    final note = pickNoteToPlay(
      letters,
      locked: recovery.lockedNoteIds,
      seed: _seed,
      step: _step,
    );
    final theme = Theme.of(context);
    if (note == null) {
      return GlassCard(
        accent: muted,
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your notes are locked on this phone. Open Notes and enter '
                'the PIN you had when you saved them.',
                key: const Key('future-note-locked'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: () => FutureLettersScreen.open(context),
              child: const Text('OPEN'),
            ),
          ],
        ),
      );
    }
    final openable = letters.length - recovery.lockedNoteIds.length;
    return GlassCard(
      key: const Key('future-note-card'),
      accent: magenta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.moment.heading, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          FutureNoteView(key: ValueKey(note.id), letter: note),
          if (openable > 1)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('future-note-another'),
                onPressed: () => setState(() => _step++),
                child: const Text('ANOTHER'),
              ),
            ),
        ],
      ),
    );
  }
}

/// One note's content: the words, or a play/stop button for a voice note.
class FutureNoteView extends ConsumerStatefulWidget {
  const FutureNoteView({required this.letter, super.key});

  final FutureLetter letter;

  @override
  ConsumerState<FutureNoteView> createState() => _FutureNoteViewState();
}

class _FutureNoteViewState extends ConsumerState<FutureNoteView> {
  VoicePlayer? _player;
  StreamSubscription<void>? _done;
  Future<String?>? _text;
  bool _playing = false;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    if (!widget.letter.isVoice) {
      _text = ref.read(recoveryProvider).readFutureLetterText(widget.letter);
    }
  }

  @override
  void dispose() {
    _done?.cancel();
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    final player = _player ??= ref.read(voicePlayerFactoryProvider)();
    _done ??= player.onComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    if (_playing) {
      await player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    final bytes = await ref
        .read(recoveryProvider)
        .readFutureLetterAudio(widget.letter);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _missing = true);
      return;
    }
    setState(() {
      _playing = true;
      _missing = false;
    });
    try {
      await player.play(bytes);
    } catch (_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _missing = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letter = widget.letter;
    if (letter.isVoice) {
      final seconds = ((letter.audio!.durationMs + 500) ~/ 1000).clamp(1, 60);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            key: const Key('future-note-play'),
            icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
            label: Text(
              _playing
                  ? 'STOP'
                  : 'PLAY YOUR VOICE NOTE (0:${'$seconds'.padLeft(2, '0')})',
            ),
            onPressed: _toggle,
          ),
          if (_missing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'This recording is not on this phone any more.',
                key: const Key('future-note-missing'),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      );
    }
    return FutureBuilder<String?>(
      future: _text,
      builder: (context, snapshot) {
        final text = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 24);
        }
        return SelectableText(
          text ?? 'This note could not be opened.',
          key: const Key('future-letter-text'),
          style: theme.textTheme.titleMedium,
        );
      },
    );
  }
}
