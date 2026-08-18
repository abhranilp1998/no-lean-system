import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../recovery/application/recovery_provider.dart';
import '../../../recovery/domain/recovery_event.dart';
import 'event_edit_dialog.dart';

class EventTile extends ConsumerWidget {
  const EventTile({required this.event, super.key});

  final RecoveryEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, icon, color) = _getEventDetails(event);

    return GlassCard(
      accent: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: displayFont(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(event.timestamp),
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                  if (event.metadata.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _MetadataView(metadata: event.metadata),
                  ]
                ],
              ),
            ),
            _ActionsMenu(event: event),
          ],
        ),
      ),
    );
  }

  (String, IconData, Color) _getEventDetails(RecoveryEvent event) {
    switch (event.type) {
      case RecoveryEventType.pledge:
        return ('PLEDGE', Icons.shield, toxic);
      case RecoveryEventType.craving:
        return ('CRAVING', Icons.bolt, magenta);
      case RecoveryEventType.sosStart:
        return ('SOS STARTED', Icons.timer, cyan);
      case RecoveryEventType.sosComplete:
        return ('SOS COMPLETED', Icons.check_circle, cyan);
      case RecoveryEventType.relapse:
        return ('RELAPSE', Icons.warning, red);
      case RecoveryEventType.cleanCheckIn:
        return ('SAFE CHECK-IN', Icons.how_to_reg, toxic);
      case RecoveryEventType.milestone:
        return ('MILESTONE', Icons.emoji_events, Colors.amber);
      case RecoveryEventType.settingsChange:
        return ('SETTING CHANGED', Icons.tune, Colors.white54);
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year} at $hour:$minute';
  }
}

class _MetadataView extends StatelessWidget {
  const _MetadataView({required this.metadata});
  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: metadata.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${e.key.toUpperCase()}: ',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(
                child: Text(
                  '${e.value}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ActionsMenu extends ConsumerWidget {
  const _ActionsMenu({required this.event});
  final RecoveryEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEditable = event.type == RecoveryEventType.craving ||
        event.type == RecoveryEventType.sosComplete;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: muted, size: 20),
      color: panelRaised,
      itemBuilder: (context) => [
        if (isEditable)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, color: cyan, size: 18),
                SizedBox(width: 8),
                Text('Edit Metadata', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: red, size: 18),
              SizedBox(width: 8),
              Text('Delete Event', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
      onSelected: (val) async {
        if (val == 'delete') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: panelRaised,
              title: const Text('Delete Event', style: TextStyle(color: Colors.white)),
              content: const Text(
                'Are you sure? This may permanently alter your computed progress stats.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('CANCEL', style: TextStyle(color: muted)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('DELETE', style: TextStyle(color: red)),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await ref.read(recoveryProvider).deleteEvent(event.id);
          }
        } else if (val == 'edit') {
          await showDialog(
            context: context,
            builder: (ctx) => EventEditDialog(event: event),
          );
        }
      },
    );
  }
}
