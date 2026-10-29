import '../../recovery/domain/recovery_event.dart';

enum HistoryCategory { recovery, settings, location }

extension HistoryCategoryCopy on HistoryCategory {
  String get label => switch (this) {
    HistoryCategory.recovery => 'Recovery',
    HistoryCategory.settings => 'Settings history',
    HistoryCategory.location => 'Location history',
  };

  String get title => switch (this) {
    HistoryCategory.recovery => 'Recovery history',
    HistoryCategory.settings => 'Settings history',
    HistoryCategory.location => 'Location history',
  };

  String get description => switch (this) {
    HistoryCategory.recovery =>
      'Your logs, check-ins, interventions and milestones.',
    HistoryCategory.settings =>
      'Recorded settings changes, with known previous and new values.',
    HistoryCategory.location =>
      'Zone observations and saved location context. Older visits can contain only a name and time.',
  };

  String get emptyMessage => switch (this) {
    HistoryCategory.recovery => 'No recovery events recorded yet.',
    HistoryCategory.settings => 'No settings changes recorded yet.',
    HistoryCategory.location =>
      'No location records yet. Automatic visit history is optional in Settings.',
  };
}

enum HistoryLocationSource { foreground, background, manual, context, unknown }

extension HistoryLocationSourceCopy on HistoryLocationSource {
  String get label => switch (this) {
    HistoryLocationSource.foreground => 'In app',
    HistoryLocationSource.background => 'Background',
    HistoryLocationSource.manual => 'Manual',
    HistoryLocationSource.context => 'Saved context',
    HistoryLocationSource.unknown => 'Unknown',
  };

  String get description => switch (this) {
    HistoryLocationSource.foreground => 'Automatic · in app',
    HistoryLocationSource.background => 'Automatic · background',
    HistoryLocationSource.manual => 'Manual · recorded source',
    HistoryLocationSource.context => 'Saved location context',
    HistoryLocationSource.unknown => 'Source not recorded or unrecognized',
  };
}

String? savedZoneName(RecoveryEvent event) {
  final value = event.metadata['zoneName'];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

/// A saved location relationship, never inferred from prose, triggers or tags.
/// Zone configuration audits are not observations of physical presence.
bool hasLocationContext(RecoveryEvent event) =>
    event.type != RecoveryEventType.settingsChange &&
    (event.type == RecoveryEventType.zoneEntry || savedZoneName(event) != null);

bool belongsToHistory(RecoveryEvent event, HistoryCategory category) =>
    switch (category) {
      HistoryCategory.recovery =>
        event.type != RecoveryEventType.settingsChange &&
            event.type != RecoveryEventType.zoneEntry,
      HistoryCategory.settings =>
        event.type == RecoveryEventType.settingsChange,
      HistoryCategory.location => hasLocationContext(event),
    };

HistoryLocationSource locationSource(RecoveryEvent event) {
  if (event.type != RecoveryEventType.zoneEntry) {
    return HistoryLocationSource.context;
  }
  return switch (event.metadata['source']) {
    'app' => HistoryLocationSource.foreground,
    'background' => HistoryLocationSource.background,
    'manual' || 'manualGps' || 'manualPin' => HistoryLocationSource.manual,
    _ => HistoryLocationSource.unknown,
  };
}

/// All supported manual aliases carry the same conservative presentation.
/// Neither a user-selected pin nor a manually saved fix proves a visit.
bool isManualLocationRecord(RecoveryEvent event) =>
    locationSource(event) == HistoryLocationSource.manual;

/// Views of the same immutable records. This never writes, clones events or
/// feeds a second event collection into recovery/money calculations.
List<RecoveryEvent> projectHistory(
  Iterable<RecoveryEvent> events,
  HistoryCategory category, {
  HistoryLocationSource? source,
  String? recordId,
}) {
  final result = events
      .where(
        (event) =>
            belongsToHistory(event, category) &&
            (recordId == null || event.id == recordId) &&
            (category != HistoryCategory.location ||
                source == null ||
                locationSource(event) == source),
      )
      .toList();
  result.sort((a, b) {
    final time = b.timestamp.compareTo(a.timestamp);
    return time != 0 ? time : a.id.compareTo(b.id);
  });
  return result;
}

String settingName(RecoveryEvent event) {
  final raw = event.metadata['field'] ?? event.metadata['setting'];
  if (raw is! String || raw.trim().isEmpty) return 'Setting not recorded';
  return raw.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
}

String settingValue(Object? value) => switch (value) {
  null => 'Not recorded',
  true || 'true' => 'On',
  false || 'false' => 'Off',
  _ => '$value',
};

Object? previousSettingValue(RecoveryEvent event) =>
    event.metadata['from'] ?? event.metadata['oldValue'];

Object? nextSettingValue(RecoveryEvent event) =>
    event.metadata['to'] ?? event.metadata['newValue'];

String savedRecordSource(RecoveryEvent event) =>
    switch (event.metadata['source']) {
      'app' => 'App',
      'background' => 'Background',
      'manual' => 'Manual',
      'import' || 'imported' => 'Imported',
      'system' || 'auto' => 'Automatic',
      final String value when value.trim().isNotEmpty => value,
      _ => 'Not recorded',
    };

/// Preserve original offset/precision text. An offset-free saved time must not
/// be silently interpreted in the current device's timezone after travel/import.
String recordedAtLabel(RecoveryEvent event) {
  final raw = event.metadata['recordedAt'] ?? event.metadata['createdAt'];
  if (raw is! String || DateTime.tryParse(raw) == null) return 'Not recorded';
  final hasOffset = RegExp(
    r'(Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(raw);
  return hasOffset ? raw : '$raw (timezone not recorded)';
}
