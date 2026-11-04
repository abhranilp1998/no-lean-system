import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../cravings/presentation/craving_dialog.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../../recovery/presentation/relapse_log_sheet.dart';
import '../data/feedback_store.dart';
import '../domain/tell_classifier.dart';

/// P1 "Tell me anything": free text, classified on the phone, answered with
/// the one action that fits. Nothing is sent anywhere.
class TellMeAnythingCard extends ConsumerStatefulWidget {
  const TellMeAnythingCard({super.key});

  @override
  ConsumerState<TellMeAnythingCard> createState() => _TellState();
}

class _TellState extends ConsumerState<TellMeAnythingCard> {
  final _text = TextEditingController();
  TellResult? _result;
  String _said = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final said = _text.text.trim();
    if (said.isEmpty) return;
    final result = classifyTell(said);
    if (result.kind == TellKind.feedback) {
      await ref.read(feedbackStoreProvider).add(said);
    }
    if (!mounted) return;
    setState(() {
      _said = said;
      _result = result;
      _text.clear();
    });
  }

  Widget _action(String key, String label, IconData icon, VoidCallback onTap) =>
      OutlinedButton.icon(
        key: ValueKey(key),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      );

  List<Widget> _reply(TellResult r) => switch (r.kind) {
    TellKind.relapse => [
      const Text(
        'Thank you for telling me. That took guts. Want to write it down so the count stays honest?',
      ),
      _action('tell-log-relapse', 'LOG IT', Icons.history, () {
        final h = r.hoursAgo;
        showRelapseLogSheet(
          context,
          source: 'tell',
          initialOccurredAt: h == null ? null : relapseHoursAgo(h),
        );
      }),
    ],
    TellKind.aboutToUse => [
      const Text(
        "I hear you. Let's just get through the next 10 minutes together.",
      ),
      _action('tell-open-sos', 'OPEN SOS', Icons.sos, () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const EmergencyScreen(),
            fullscreenDialog: true,
          ),
        );
      }),
      _action(
        'tell-log-craving',
        'LOG CRAVING',
        Icons.waves,
        () => showCravingDialog(context, ref),
      ),
    ],
    TellKind.feedback => [
      const Text(
        'Saved for AP (the developer). It stays on this phone until you export it.',
      ),
    ],
    TellKind.other => [
      const Text(
        "Got it. Nothing logged. If it's about the app, I can keep it for AP.",
      ),
      _action(
        'tell-save-feedback',
        'KEEP FOR AP',
        Icons.feedback_outlined,
        () async {
          await ref.read(feedbackStoreProvider).add(_said);
          if (mounted) {
            setState(() => _result = const TellResult(TellKind.feedback));
          }
        },
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return GlassCard(
      accent: cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TELL ME ANYTHING', style: eyebrowStyle.copyWith(color: cyan)),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('tell-input'),
            controller: _text,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              hintText: 'What happened, what you feel, or what to fix…',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('tell-submit'),
            onPressed: _submit,
            child: const Text('TELL'),
          ),
          if (r != null) ...[
            const SizedBox(height: 10),
            for (final w in _reply(r))
              Padding(padding: const EdgeInsets.only(bottom: 6), child: w),
          ],
        ],
      ),
    );
  }
}
