import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../recovery/application/recovery_provider.dart';
import '../application/note_invite_store.dart';
import '../domain/note_invite.dart';
import 'note_composer.dart';

/// Whether it is a good time to invite right now (and remembers that we did).
Future<bool> noteInviteDue(WidgetRef ref, {DateTime? now}) async {
  final time = now ?? DateTime.now();
  final recovery = ref.read(recoveryProvider);
  if (!recovery.isLoaded) return false;
  final store = ref.read(noteInviteStoreProvider);
  final due = shouldInviteNote(
    state: await store.read(),
    now: time,
    noteCount: recovery.futureLetters.length,
  );
  return due;
}

/// Invites the user, once and gently, to leave a note. Does nothing when it is
/// not a good time. Call after a good moment: a milestone, a clean check-in,
/// or an urge that passed (PR #39's daily check-in can call this too).
Future<void> maybeShowNoteInviteSheet(
  BuildContext context,
  WidgetRef ref,
  NoteInviteOccasion occasion,
) async {
  if (!await noteInviteDue(ref) || !context.mounted) return;
  await showNoteInviteSheet(context, ref, occasion);
}

Future<void> showNoteInviteSheet(
  BuildContext context,
  WidgetRef ref,
  NoteInviteOccasion occasion,
) async {
  await ref.read(noteInviteStoreProvider).shown(DateTime.now());
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => NoteInviteSheet(occasion: occasion),
  );
}

class NoteInviteSheet extends ConsumerStatefulWidget {
  const NoteInviteSheet({required this.occasion, super.key});

  final NoteInviteOccasion occasion;

  @override
  ConsumerState<NoteInviteSheet> createState() => _NoteInviteSheetState();
}

class _NoteInviteSheetState extends ConsumerState<NoteInviteSheet> {
  bool _open = false;
  bool _saved = false;

  Future<void> _notNow() async {
    await ref
        .read(noteInviteStoreProvider)
        .snooze(DateTime.now(), const Duration(days: 3));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _never() async {
    await ref.read(noteInviteStoreProvider).never();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + inset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.occasion.headline,
            style: theme.textTheme.labelLarge?.copyWith(color: magenta),
          ),
          const SizedBox(height: 8),
          Text(widget.occasion.line, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'It stays on this phone, and shows up when an urge or a hard '
            'evening hits. Totally optional.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          if (_saved)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Saved. It will be there when you need it.',
                  key: const Key('note-invite-saved'),
                  style: theme.textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('DONE'),
                ),
              ],
            )
          else if (_open)
            FutureNoteComposer(
              compact: true,
              saveLabel: 'SAVE NOTE',
              onSaved: () => setState(() => _saved = true),
            )
          else
            FilledButton(
              key: const Key('note-invite-open'),
              onPressed: () => setState(() => _open = true),
              child: const Text('WRITE OR RECORD A NOTE'),
            ),
          if (!_saved) ...[
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton(
                  key: const Key('note-invite-later'),
                  onPressed: _notNow,
                  child: const Text('NOT NOW'),
                ),
                TextButton(
                  key: const Key('note-invite-never'),
                  onPressed: _never,
                  child: const Text("DON'T SUGGEST THIS"),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A quiet in-screen link: shown only when an invitation is due. Tapping it
/// opens the sheet. Shows nothing otherwise.
class FutureNoteInviteLink extends ConsumerStatefulWidget {
  const FutureNoteInviteLink({required this.occasion, super.key});

  final NoteInviteOccasion occasion;

  @override
  ConsumerState<FutureNoteInviteLink> createState() =>
      _FutureNoteInviteLinkState();
}

class _FutureNoteInviteLinkState extends ConsumerState<FutureNoteInviteLink> {
  bool _due = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final due = await noteInviteDue(ref);
    if (!mounted || !due) return;
    // Offering counts as asking: it will not be offered again soon.
    await ref.read(noteInviteStoreProvider).shown(DateTime.now());
    if (mounted) setState(() => _due = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_due) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const Key('note-invite-link'),
      icon: const Icon(Icons.mail_outline),
      label: const Text('LEAVE A NOTE FOR A HARD DAY'),
      onPressed: () async {
        setState(() => _due = false);
        await showNoteInviteSheet(context, ref, widget.occasion);
      },
    );
  }
}
