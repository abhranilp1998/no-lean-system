import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';

/// Asks for a PIN for notes (unlocking old notes, or locking them). Returns
/// the digits, or null if cancelled.
Future<String?> showNotePinDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) => showDialog<String>(
  context: context,
  builder: (_) => _NotePinDialog(
    title: title,
    message: message,
    confirmLabel: confirmLabel,
  ),
);

class _NotePinDialog extends StatefulWidget {
  const _NotePinDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<_NotePinDialog> createState() => _NotePinDialogState();
}

class _NotePinDialogState extends State<_NotePinDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _controller.text;
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      setState(() => _error = 'A PIN is 4 to 8 digits.');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: widget.title,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.message,
          style: const TextStyle(color: muted, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('note-pin-field'),
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
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              key: const Key('note-pin-submit'),
              onPressed: _submit,
              child: Text(widget.confirmLabel),
            ),
          ],
        ),
      ],
    ),
  );
}
