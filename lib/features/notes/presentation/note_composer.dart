import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../letters/domain/future_letter.dart';
import '../../recovery/application/recovery_provider.dart';
import '../services/voice_io.dart';
import 'voice_note_recorder.dart';

/// Write or record a note to your future self.
class FutureNoteComposer extends ConsumerStatefulWidget {
  const FutureNoteComposer({
    this.onSaved,
    this.compact = false,
    this.saveLabel = 'SEAL NOTE',
    super.key,
  });

  final VoidCallback? onSaved;
  final bool compact;
  final String saveLabel;

  @override
  ConsumerState<FutureNoteComposer> createState() => _FutureNoteComposerState();
}

class _FutureNoteComposerState extends ConsumerState<FutureNoteComposer> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _saveText() async {
    try {
      await ref.read(recoveryProvider).addFutureLetter(_draft.text);
      _draft.clear();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      widget.onSaved?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  Future<void> _saveVoice(VoiceTake take) async {
    await ref.read(recoveryProvider).addVoiceNote(take.bytes, take.length);
    if (!mounted) return;
    AppNotice.show(
      context,
      'Voice note kept. It stays on this phone.',
      type: AppNoticeType.success,
    );
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('future-letter-draft'),
          controller: _draft,
          minLines: widget.compact ? 2 : 3,
          maxLines: 8,
          maxLength: FutureLetter.maxLength,
          decoration: const InputDecoration(
            labelText: 'Write to yourself, for a future evening',
          ),
        ),
        FilledButton(
          key: const Key('future-letter-save'),
          onPressed: _saveText,
          child: Text(widget.saveLabel),
        ),
        const SizedBox(height: 12),
        VoiceNoteRecorder(onSave: _saveVoice),
      ],
    );
  }
}
