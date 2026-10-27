import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/services/app_notice.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../recovery/application/recovery_controller.dart';
import '../../../recovery/application/recovery_provider.dart';
import '../../../recovery/domain/dose_units.dart';
import '../../../recovery/domain/recovery_event.dart';
import '../../../recovery/domain/relapse_log_entry.dart';
import '../../../recovery/presentation/relapse_auth_dialog.dart';
import '../../domain/history_projection.dart';
import 'event_edit_dialog.dart';
import 'history_record_facts.dart';

class EventTile extends ConsumerWidget {
  const EventTile({required this.event, super.key});

  final RecoveryEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (label, icon, color) = _getEventDetails(event);

    if (event.type == RecoveryEventType.relapse) {
      return _RelapseEventCard(
        event: event,
        formattedDate: _formatDate(event.timestamp),
      );
    }

    return GlassCard(
      accent: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final badge = Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            );
            final details = Column(
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
                  event.type == RecoveryEventType.daySummary
                      ? '${event.metadata['date']} · Time and event count were not recorded'
                      : _formatDate(event.timestamp),
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                if (event.metadata.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (event.type == RecoveryEventType.settingsChange)
                    SettingsChangeFacts(event: event)
                  else if (event.type == RecoveryEventType.zoneEntry)
                    LocationRecordFacts(event: event)
                  else
                    _MetadataView(metadata: event.metadata),
                ],
              ],
            );
            final actions =
                _ActionsMenu.isEditable(event) || _ActionsMenu.canDelete(event)
                ? _ActionsMenu(event: event)
                : null;
            final stacked =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 21;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [badge, const Spacer(), ?actions]),
                  const SizedBox(height: 12),
                  details,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                badge,
                const SizedBox(width: 14),
                Expanded(child: details),
                ?actions,
              ],
            );
          },
        ),
      ),
    );
  }

  (String, IconData, Color) _getEventDetails(RecoveryEvent event) {
    switch (event.type) {
      case RecoveryEventType.daySummary:
        return (
          event.metadata['clean'] == true
              ? 'LEGACY CLEAN DAY'
              : 'LEGACY RELAPSE DAY',
          Icons.calendar_month,
          event.metadata['clean'] == true ? toxic : red,
        );
      case RecoveryEventType.recoveryStart:
        return ('RECOVERY STARTED', Icons.flag, toxic);
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
      case RecoveryEventType.zoneEntry:
        return (
          '${isManualLocationRecord(event) ? 'LOCATION SAVED' : 'ZONE OBSERVED'} // ${event.metadata['zoneName']}',
          Icons.place_outlined,
          red,
        );
      case RecoveryEventType.cravingCheck:
        return (
          'CRAVING RECHECK // ${'${event.metadata['outcome']}'.toUpperCase()}',
          Icons.update,
          magenta,
        );
      case RecoveryEventType.appUnlock:
        final zone = event.metadata['zoneName'];
        return (
          'APP UNLOCKED // ${event.metadata['appLabel']} // '
              '${'${event.metadata['reason']}'.toUpperCase()}'
              '${zone is String ? ' // IN $zone' : ''}',
          Icons.lock_open,
          Colors.amber,
        );
      case RecoveryEventType.codeSession:
        return (
          event.metadata['completed'] == true
              ? 'CODE BLOCK DONE'
              : 'CODE BLOCK STOPPED',
          Icons.code,
          purple,
        );
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

class _RelapseEventCard extends StatelessWidget {
  const _RelapseEventCard({required this.event, required this.formattedDate});

  final RecoveryEvent event;
  final String formattedDate;

  @override
  Widget build(BuildContext context) {
    final relapseType = RelapseTypeLabel.fromName(
      event.metadata['relapseType'],
    );
    final note = event.metadata['note'] as String?;
    final quantity = event.metadata['quantity'] as String?;
    final attemptedSos = event.metadata['attemptedSos'] as bool?;
    final dose = DoseAmount.fromMetadata(event.metadata);
    final showQuantity =
        quantity?.isNotEmpty == true &&
        (dose == null || event.metadata['amountSource'] != 'parsed');
    final cost = event.metadata['cost'];
    final stress = event.metadata['stress'];
    final streakLost = event.metadata['streakLost'];
    final contextTags = switch (event.metadata['contextTags']) {
      final List values => values.whereType<String>().toList(),
      _ => const <String>[],
    };

    return Semantics(
      container: true,
      label: [
        'Relapse recorded $formattedDate.',
        if (relapseType != null) 'Type ${relapseType.label}.',
        if (dose != null) 'Amount ${dose.display}.',
        if (cost is num) 'Cost ${money(cost)}.',
        if (stress is num) 'Stress $stress of 5.',
        if (attemptedSos != null)
          attemptedSos ? 'SOS was attempted.' : 'SOS was not attempted.',
        if (contextTags.isNotEmpty)
          'Context signals: ${contextTags.join(', ')}.',
        if (note?.isNotEmpty == true) 'Note: $note',
      ].join(' '),
      child: Container(
        decoration: BoxDecoration(
          color: red.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: red.withValues(alpha: .82), width: 2),
          boxShadow: [
            BoxShadow(
              color: red.withValues(alpha: .14),
              blurRadius: 22,
              spreadRadius: -5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 7, color: red),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: red,
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                'RELAPSE',
                                style: displayFont(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                            const Spacer(),
                            ExcludeSemantics(child: _ActionsMenu(event: event)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          relapseType?.label ?? 'LEGACY RELAPSE RECORD',
                          style: displayFont(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formattedDate,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                        if (note?.isNotEmpty == true) ...[
                          const SizedBox(height: 12),
                          Text(
                            note!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in contextTags)
                              _RelapseFact(icon: Icons.bolt, label: tag),
                            if (attemptedSos != null)
                              _RelapseFact(
                                icon: attemptedSos
                                    ? Icons.sos
                                    : Icons.sos_outlined,
                                label: attemptedSos
                                    ? 'SOS ATTEMPTED'
                                    : 'NO SOS ATTEMPT',
                              ),
                            if (dose != null)
                              _RelapseFact(
                                icon: Icons.science_outlined,
                                label: dose.display.toUpperCase(),
                              ),
                            if (showQuantity)
                              _RelapseFact(
                                icon: Icons.straighten,
                                label: quantity!,
                              ),
                            if (cost is num)
                              _RelapseFact(
                                icon: Icons.currency_rupee,
                                label: money(cost),
                              ),
                            if (stress is num)
                              _RelapseFact(
                                icon: Icons.speed,
                                label: 'STRESS $stress/5',
                              ),
                            if (streakLost != null)
                              _RelapseFact(
                                icon: Icons.timer_off_outlined,
                                label: '$streakLost DAYS INTERRUPTED',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RelapseFact extends StatelessWidget {
  const _RelapseFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: red.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: red, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataView extends StatelessWidget {
  const _MetadataView({required this.metadata});
  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: metadata.entries
          .where(
            (e) => !{
              'batchId',
              'source',
              'recordedAt',
              'startId',
              'date',
              'clean',
              'taskId',
              'zoneId',
              'plannedSeconds',
              'cravingId',
            }.contains(e.key),
          )
          .map((e) {
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
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(),
    );
  }
}

class _ActionsMenu extends ConsumerWidget {
  const _ActionsMenu({required this.event});
  final RecoveryEvent event;

  static bool isEditable(RecoveryEvent event) =>
      event.type == RecoveryEventType.craving ||
      event.type == RecoveryEventType.sosComplete;

  /// Auto milestones are facts derived from the streak; deleting one would
  /// only see it recorded again.
  static bool canDelete(RecoveryEvent event) =>
      event.type != RecoveryEventType.recoveryStart &&
      !(event.type == RecoveryEventType.milestone &&
          event.metadata['source'] == 'auto');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEditable = _ActionsMenu.isEditable(event);
    final canDelete = _ActionsMenu.canDelete(event);

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
        if (canDelete)
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
        try {
          if (val == 'delete') {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: panelRaised,
                title: const Text(
                  'Delete Event',
                  style: TextStyle(color: Colors.white),
                ),
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
              final recovery = ref.read(recoveryProvider);
              var result = await recovery.deleteEvent(id: event.id);
              if (result == ProtectedActionResult.authenticationRequired &&
                  context.mounted) {
                final pin = await showRelapsePinDialog(
                  context,
                  actionLabel: 'AUTHORIZE DELETE',
                );
                if (pin == null) return;
                result = await recovery.deleteEvent(
                  id: event.id,
                  pin: pin,
                  tryBiometrics: false,
                );
              }
              if (result != ProtectedActionResult.completed &&
                  context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result == ProtectedActionResult.lockedOut
                          ? result.failureMessage
                          : 'Authentication failed. History was not changed.',
                    ),
                    backgroundColor: red,
                  ),
                );
              }
            }
          } else if (val == 'edit') {
            await showDialog(
              context: context,
              builder: (ctx) => EventEditDialog(event: event),
            );
          }
        } catch (_) {
          if (context.mounted) {
            AppNotice.show(
              context,
              'History could not be changed. Please try again.',
              type: AppNoticeType.error,
            );
          }
        }
      },
    );
  }
}
