import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../notes/presentation/future_note_card.dart';
import '../../notes/presentation/note_composer.dart';
import '../../notes/presentation/note_pin_dialog.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/presentation/relapse_auth_dialog.dart';
import '../domain/future_letter.dart';

/// Notes from future you. Opens only after the PIN/biometric check when a
/// PIN is set; the widget never carries any of this text.
class FutureLettersScreen extends ConsumerStatefulWidget {
  const FutureLettersScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const FutureLettersScreen()));

  @override
  ConsumerState<FutureLettersScreen> createState() =>
      _FutureLettersScreenState();
}

class _FutureLettersScreenState extends ConsumerState<FutureLettersScreen> {
  bool _unlocked = false;
  bool _failed = false;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authorize());
  }

  Future<void> _authorize() async {
    final recovery = ref.read(recoveryProvider);
    var result = await recovery.authorizeFutureLetters();
    if (result == ProtectedActionResult.authenticationRequired && mounted) {
      final pin = await showRelapsePinDialog(context, actionLabel: 'OPEN NOTE');
      if (pin == null) {
        result = ProtectedActionResult.denied;
      } else {
        result = await recovery.authorizeFutureLetters(
          pin: pin,
          tryBiometrics: false,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _unlocked = result == ProtectedActionResult.completed;
      _failed = !_unlocked;
    });
    if (_unlocked) await recovery.refreshNoteState();
  }

  Future<void> _unlockWithOldPin() async {
    final pin = await showNotePinDialog(
      context,
      title: 'UNLOCK NOTES',
      message:
          'Enter the PIN you had when you saved these notes. It is only used '
          'to open them on this phone: nothing is sent anywhere, and a wrong '
          'PIN changes nothing.',
      confirmLabel: 'UNLOCK',
    );
    if (pin == null || !mounted) return;
    final result = await ref.read(recoveryProvider).unlockFutureNotes(pin);
    if (!mounted) return;
    AppNotice.show(
      context,
      result.wrongPin
          ? 'That PIN did not open these notes. Nothing was changed. Try the '
                'PIN you had when you saved them.'
          : result.stillLocked > 0
          ? '${result.opened} opened. ${result.stillLocked} need a different PIN.'
          : '${result.opened} note${result.opened == 1 ? '' : 's'} unlocked.',
      type: result.wrongPin ? AppNoticeType.error : AppNoticeType.success,
    );
  }

  Future<void> _turnOnEncryption() async {
    final pin = await showRelapsePinDialog(context, actionLabel: 'LOCK NOTES');
    if (pin == null || !mounted) return;
    final recovery = ref.read(recoveryProvider);
    final result = await recovery.enableNoteEncryption(pin);
    if (!mounted) return;
    AppNotice.show(
      context,
      result == ProtectedActionResult.completed
          ? (recovery.futureNotesEncrypted
                ? 'Your notes are now locked with your PIN.'
                : 'Could not lock notes on this phone. They are unchanged.')
          : result.failureMessage,
      type:
          result == ProtectedActionResult.completed &&
              recovery.futureNotesEncrypted
          ? AppNoticeType.success
          : AppNoticeType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('NOTES FROM FUTURE YOU')),
      body: !_unlocked
          ? Center(
              child: _failed
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Locked.'),
                        TextButton(
                          onPressed: _authorize,
                          child: const Text('TRY AGAIN'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            )
          : _body(recovery),
    );
  }

  Widget _body(RecoveryController recovery) {
    final letters = recovery.futureLetters;
    final locked = recovery.lockedNoteIds;
    final openable = [
      for (final l in letters)
        if (!locked.contains(l.id)) l,
    ];
    final tonight = recovery.tonightLetter;
    FutureLetter? shown;
    if (openable.isNotEmpty) {
      final start = tonight == null
          ? 0
          : openable.indexWhere((l) => l.id == tonight.id);
      shown = openable[((start < 0 ? 0 : start) + _offset) % openable.length];
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (locked.isNotEmpty) ...[
          _LockedPanel(count: locked.length, onUnlock: _unlockWithOldPin),
          const SizedBox(height: 16),
        ],
        if (shown == null)
          Text(
            letters.isEmpty
                ? 'No notes yet. Write or record one for a hard evening.'
                : 'Your notes are locked.',
          )
        else ...[
          Text(
            _offset == 0 ? 'TONIGHT' : 'ANOTHER NOTE',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: FutureNoteView(key: ValueKey(shown.id), letter: shown),
            ),
          ),
          Row(
            children: [
              if (openable.length > 1)
                TextButton.icon(
                  key: const Key('future-letter-next'),
                  icon: const Icon(Icons.navigate_next),
                  label: const Text('NEXT'),
                  onPressed: () => setState(() => _offset++),
                ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final id = shown!.id;
                  await recovery.deleteFutureLetter(id);
                  if (mounted) setState(() => _offset = 0);
                },
                child: const Text('DELETE'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        const FutureNoteComposer(),
        const SizedBox(height: 12),
        Text(
          '${letters.length} saved. One opens each evening, and they can '
          'also come up when you ride out an urge or after a slip. The '
          'home-screen widget never shows them.',
          style: theme.textTheme.bodySmall,
        ),
        if (letters.any((l) => locked.contains(l.id)))
          for (final l in letters.where((l) => locked.contains(l.id)))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(l.isVoice ? Icons.mic_none : Icons.lock_outline),
              title: Text(l.isVoice ? 'Locked voice note' : 'Locked note'),
              subtitle: Text('Saved ${_date(l.createdAt)}'),
              trailing: IconButton(
                key: Key('future-note-delete-${l.id}'),
                tooltip: 'Delete this note',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => recovery.deleteFutureLetter(l.id),
              ),
            ),
        const SizedBox(height: 20),
        _SecurityPanel(
          encrypted: recovery.futureNotesEncrypted,
          hasPin: recovery.requirePinAfterRelapse,
          onLock: _turnOnEncryption,
        ),
      ],
    );
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _LockedPanel extends StatelessWidget {
  const _LockedPanel({required this.count, required this.onUnlock});

  final int count;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      accent: red,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count NOTE${count == 1 ? '' : 'S'} LOCKED',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'This phone does not hold the key for '
            '${count == 1 ? 'this note' : 'these notes'}: it came from a '
            'backup, a reinstall or another phone. Enter the PIN you had '
            'when you saved ${count == 1 ? 'it' : 'them'}. They are kept, '
            'not deleted, and nothing else is affected.',
            key: const Key('future-notes-locked-explainer'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('future-notes-unlock'),
            onPressed: onUnlock,
            child: const Text('ENTER THE OLD PIN'),
          ),
          const SizedBox(height: 6),
          Text(
            'If that PIN is forgotten, these notes cannot be opened by '
            'anyone, including us. You can delete them below.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({
    required this.encrypted,
    required this.hasPin,
    required this.onLock,
  });

  final bool encrypted;
  final bool hasPin;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      accent: muted,
      child: Column(
        key: const Key('future-notes-security'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            encrypted ? 'LOCKED WITH YOUR PIN' : 'HOW YOUR NOTES ARE KEPT',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          if (encrypted) ...[
            Text(
              'Notes and voice recordings are encrypted on this phone. The '
              'key lives in the phone secure storage, so they open here '
              'without typing the PIN again.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '• Changing your PIN keeps every note working.\n'
              '• Removing your PIN turns encryption off and decrypts your '
              'notes back to normal storage first. Nothing is lost.\n'
              '• Reinstalling, or restoring on a new phone, needs the PIN '
              'you had when you saved them. There is no reset: if it is '
              'forgotten, nobody can open those notes, including us. Your '
              'other data is unaffected.\n'
              '• A short PIN is a lock, not a vault. Keep backup files '
              'private.',
              key: const Key('future-notes-security-details'),
              style: theme.textTheme.bodySmall,
            ),
          ] else if (hasPin) ...[
            Text(
              'Your notes are not encrypted yet. Enter your PIN once to lock '
              'them: new notes will be locked automatically after that.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            FilledButton(
              key: const Key('future-notes-lock'),
              onPressed: onLock,
              child: const Text('LOCK NOTES WITH MY PIN'),
            ),
          ] else
            Text(
              'Notes are stored on this phone only and are not encrypted. Set '
              'a PIN in Settings and they will be locked with it.',
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 6),
          Text(
            'Nothing is uploaded. Notes and voice recordings are included '
            'in backups you export (locked, if a PIN was set). If a backup '
            'would go over 5 MB, the newest recordings go in first; any '
            'left out stay on this phone and the export tells you.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
