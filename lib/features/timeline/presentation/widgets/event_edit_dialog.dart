import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glow_button.dart';
import '../../../recovery/application/recovery_provider.dart';
import '../../../recovery/domain/recovery_event.dart';

class EventEditDialog extends ConsumerStatefulWidget {
  const EventEditDialog({required this.event, super.key});
  final RecoveryEvent event;

  @override
  ConsumerState<EventEditDialog> createState() => _EventEditDialogState();
}

class _EventEditDialogState extends ConsumerState<EventEditDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    const encoder = JsonEncoder.withIndent('  ');
    _controller = TextEditingController(text: encoder.convert(widget.event.metadata));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final decoded = jsonDecode(_controller.text);
      if (decoded is! Map<String, dynamic>) {
        setState(() => _error = 'Must be a valid JSON object');
        return;
      }
      ref.read(recoveryProvider).editEventMetadata(widget.event.id, decoded);
      Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'Invalid JSON: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cyan.withValues(alpha: .3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'EDIT METADATA',
              style: displayFont(fontSize: 16, fontWeight: FontWeight.bold, color: cyan),
            ),
            const SizedBox(height: 16),
            const Text(
              'Warning: Modifying metadata manually can break insights. Edit as valid JSON.',
              style: TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black45,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
                ),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL', style: TextStyle(color: muted)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlowButton(
                    label: 'SAVE',
                    icon: Icons.save,
                    color: cyan,
                    onTap: _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
