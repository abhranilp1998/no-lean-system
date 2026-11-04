import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../recovery/domain/recovery_event.dart';
import '../../domain/history_projection.dart';

class HistoryFact extends StatelessWidget {
  const HistoryFact({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
      ],
    ),
  );
}

class SettingsChangeFacts extends StatelessWidget {
  const SettingsChangeFacts({required this.event, super.key});

  final RecoveryEvent event;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      HistoryFact(label: 'Setting', value: settingName(event)),
      HistoryFact(
        label: 'Previous',
        value: settingValue(previousSettingValue(event)),
      ),
      HistoryFact(label: 'New', value: settingValue(nextSettingValue(event))),
      HistoryFact(label: 'Source', value: savedRecordSource(event)),
    ],
  );
}

class LocationRecordFacts extends StatelessWidget {
  const LocationRecordFacts({required this.event, super.key});

  final RecoveryEvent event;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      HistoryFact(label: 'Source', value: locationSource(event).description),
      const Text(
        'Saved zone/context reference. Exact position and accuracy are not verified by this record.',
        style: TextStyle(color: muted, fontSize: 11, height: 1.4),
      ),
      if (isManualLocationRecord(event))
        const Text(
          'User-selected location; this does not establish presence.',
          style: TextStyle(color: muted, fontSize: 11, height: 1.4),
        ),
    ],
  );
}
