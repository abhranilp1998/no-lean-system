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
          const Text(
            'Biometric verification was unavailable or cancelled. Enter your NO LEAN PIN to continue.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (value) {
              if (value.length >= 4) Navigator.pop(context, value);
            },
            decoration: const InputDecoration(
              labelText: '4–6 digit PIN',
              prefixIcon: Icon(Icons.password, color: magenta),
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
                onPressed: () {
                  if (_controller.text.length < 4) return;
                  Navigator.pop(context, _controller.text);
                },
                style: FilledButton.styleFrom(backgroundColor: magenta),
                child: Text(widget.actionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
