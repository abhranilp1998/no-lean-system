import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../services/backup_service.dart';

class BackupImportChoice {
  const BackupImportChoice({required this.restorePreferences});

  final bool restorePreferences;
}

class BackupPreviewSheet extends StatefulWidget {
  const BackupPreviewSheet({
    required this.preview,
    required this.onConfirm,
    super.key,
  });

  final BackupPreview preview;
  final ValueChanged<bool> onConfirm;

  static Future<BackupImportChoice?> show(
    BuildContext context,
    BackupPreview preview,
  ) {
    return showModalBottomSheet<BackupImportChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BackupPreviewSheet(
        preview: preview,
        onConfirm: (restorePreferences) => Navigator.pop(
          context,
          BackupImportChoice(restorePreferences: restorePreferences),
        ),
      ),
    );
  }

  @override
  State<BackupPreviewSheet> createState() => _BackupPreviewSheetState();
}

class _BackupPreviewSheetState extends State<BackupPreviewSheet> {
  bool _restorePreferences = false;

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('MMM d, yyyy - h:mm a');
    final preview = widget.preview;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'IMPORT BACKUP',
              style: TextStyle(
                fontFamily: 'NoLeanDisplay',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GlassCard(
              accent: cyan,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Row('Total Events', '${preview.eventCount}', cyan),
                  const Divider(color: Colors.white12, height: 24),
                  _Row(
                    'Oldest Record',
                    preview.oldestEventDate != null
                        ? format.format(preview.oldestEventDate!)
                        : 'N/A',
                    muted,
                  ),
                  const SizedBox(height: 12),
                  _Row(
                    'Newest Record',
                    preview.newestEventDate != null
                        ? format.format(preview.newestEventDate!)
                        : 'N/A',
                    muted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Events are merged without replacing matching IDs. The encrypted relapse PIN and trusted contact are never included in a backup.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
            if (preview.hasPreferences) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _restorePreferences,
                activeColor: cyan,
                title: const Text(
                  'Restore personalizations',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                subtitle: const Text(
                  'Reasons, reminders, spend, risk window, cooldown, and interface preferences.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                onChanged: (value) =>
                    setState(() => _restorePreferences = value ?? false),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => widget.onConfirm(_restorePreferences),
              child: const Text('MERGE BACKUP DATA'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: muted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, this.valueColor);

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: muted)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
