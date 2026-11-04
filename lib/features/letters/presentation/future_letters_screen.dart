import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final _draft = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authorize());
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
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
  }

  Future<void> _save() async {
    final text = _draft.text;
    try {
      await ref.read(recoveryProvider).addFutureLetter(text);
      _draft.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
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
    final tonight = recovery.tonightLetter;
    FutureLetter? shown;
    if (tonight != null) {
      final start = letters.indexWhere((l) => l.id == tonight.id);
      shown = letters[(start + _offset) % letters.length];
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (shown == null)
          const Text('No notes yet. Write one for a hard evening.')
        else ...[
          Text(
            _offset == 0 ? 'TONIGHT' : 'ANOTHER NOTE',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: SelectableText(
                shown.text,
                key: const Key('future-letter-text'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          Row(
            children: [
              if (letters.length > 1)
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
        TextField(
          key: const Key('future-letter-draft'),
          controller: _draft,
          minLines: 3,
          maxLines: 8,
          maxLength: FutureLetter.maxLength,
          decoration: const InputDecoration(
            labelText: 'Write to yourself, for a future evening',
          ),
        ),
        FilledButton(
          key: const Key('future-letter-save'),
          onPressed: _save,
          child: const Text('SEAL NOTE'),
        ),
        const SizedBox(height: 12),
        Text(
          '${letters.length} sealed. One opens each evening. '
          'The home-screen widget never shows the text.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
