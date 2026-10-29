import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/tab_layout.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/recovery_event.dart';
import '../domain/history_projection.dart';
import 'widgets/event_tile.dart';
import 'widgets/history_record_facts.dart';

class HistoryRecordScreen extends ConsumerWidget {
  const HistoryRecordScreen({
    required this.recordId,
    required this.category,
    required this.onOpenHistory,
    super.key,
  });

  final String recordId;
  final HistoryCategory category;
  final ValueChanged<HistoryCategory> onOpenHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref
        .watch(recoveryProvider)
        .events
        .where((event) => event.id == recordId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Record details')),
      body: SafeArea(
        child: event == null
            ? const Center(child: Text('This record is no longer in history.'))
            : TabListView(
                children: [
                  EventTile(event: event),
                  const SizedBox(height: 16),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HistoryFact(
                          label: 'Happened at',
                          value: event.type == RecoveryEventType.daySummary
                              ? '${event.metadata['date']} · time not recorded'
                              : DateFormat(
                                  'dd MMM yyyy · HH:mm:ss',
                                ).format(event.timestamp.toLocal()),
                        ),
                        if (event.type != RecoveryEventType.daySummary)
                          const Text(
                            'Event time is shown in this device\'s local timezone.',
                          ),
                        const SizedBox(height: 10),
                        HistoryFact(
                          label: 'Recorded at',
                          value: recordedAtLabel(event),
                        ),
                        if (event.type != RecoveryEventType.zoneEntry &&
                            event.type != RecoveryEventType.settingsChange)
                          HistoryFact(
                            label: 'Source',
                            value: savedRecordSource(event),
                          ),
                        if (hasLocationContext(event) &&
                            event.type != RecoveryEventType.zoneEntry) ...[
                          HistoryFact(
                            label: 'Saved place',
                            value: savedZoneName(event)!,
                          ),
                          LocationRecordFacts(event: event),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final destination in HistoryCategory.values)
                    if (destination != category &&
                        belongsToHistory(event, destination))
                      OutlinedButton.icon(
                        key: ValueKey('history-crosslink-${destination.name}'),
                        onPressed: () => onOpenHistory(destination),
                        icon: const Icon(Icons.tab),
                        label: Text('View in ${destination.title}'),
                      ),
                  ExpansionTile(
                    title: const Text('Technical details'),
                    children: [
                      HistoryFact(label: 'Record ID', value: event.id),
                      HistoryFact(label: 'Stored type', value: event.type.name),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
