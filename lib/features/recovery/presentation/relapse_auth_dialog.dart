import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';

Future<String?> showRelapsePinDialog(
  BuildContext context, {
  required String actionLabel,
}) async {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _RelapsePinDialog(actionLabel: actionLabel),
  );
}

class _RelapsePinDialog extends StatefulWidget {
  const _RelapsePinDialog({required this.actionLabel});
  final String actionLabel;

  @override
  State<_RelapsePinDialog> createState() => _RelapsePinDialogState();
}

class _RelapsePinDialogState extends State<_RelapsePinDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'RELAPSE LOCK // PIN',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: magenta.withValues(alpha: 0.08),
              border: Border.all(color: magenta.withValues(alpha: 0.55)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: magenta, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Biometrics did not complete. Enter your local NO LEAN PIN. Five incorrect attempts pause PIN entry for five minutes.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '4–8 digit PIN',
              errorText: _error,
              prefixIcon: const Icon(Icons.password, color: magenta),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(backgroundColor: magenta),
                child: Text(widget.actionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    final pin = _controller.text;
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      setState(() => _error = 'Enter 4–8 digits.');
      return;
    }
    Navigator.pop(context, pin);
  }
}
