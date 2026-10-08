import 'dart:convert';

import 'recovery_event.dart';

/// Column order for the history CSV. Stable: append new columns at the end.
const eventsCsvColumns = [
  'id',
  'type',
  'timestamp',
  'date',
  'intensity',
  'trigger',
  'relapse_type',
  'quantity',
  'attempted_sos',
  'post_sos',
  'streak_lost',
  'context_tags',
  'debrief',
  'duration_seconds',
  'milestone_days',
  'setting',
  'note',
  'details',
];

/// Metadata keys that have their own column; everything else goes to
/// `details` as JSON so no recorded fact is dropped.
const _mappedKeys = {
  'date',
  'intensity',
  'trigger',
  'relapseType',
  'quantity',
  'attemptedSos',
  'postSos',
  'streakLost',
  'contextTags',
  'debrief',
  'durationSeconds',
  'days',
  'setting',
  'field',
  'note',
};

/// Builds an RFC 4180 CSV of every event, oldest first, with CRLF line
/// endings, a UTF-8 BOM (so spreadsheet apps detect UTF-8), ISO 8601
/// timestamps with the UTC offset, and spreadsheet-formula neutralisation for
/// free-text cells.
String buildEventsCsv(Iterable<RecoveryEvent> events) {
  final sorted = events.toList()
    ..sort((a, b) {
      final byTime = a.timestamp.compareTo(b.timestamp);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  final buffer = StringBuffer('\uFEFF')
    ..write(eventsCsvColumns.join(','))
    ..write('\r\n');
  for (final event in sorted) {
    buffer
      ..write(eventCsvRow(event).join(','))
      ..write('\r\n');
  }
  return buffer.toString();
}

List<String> eventCsvRow(RecoveryEvent event) {
  final m = event.metadata;
  String text(Object? value) => value == null ? '' : csvText('$value');
  String plain(Object? value) => value == null ? '' : csvEscape('$value');
  String flag(Object? value) => value is bool ? (value ? 'true' : 'false') : '';
  final extra = {
    for (final entry in m.entries)
      if (!_mappedKeys.contains(entry.key)) entry.key: entry.value,
  };
  final tags = m['contextTags'];
  return [
    plain(event.id),
    plain(event.type.name),
    plain(isoWithOffset(event.timestamp)),
    plain(m['date'] ?? isoWithOffset(event.timestamp).substring(0, 10)),
    plain(m['intensity']),
    text(m['trigger']),
    plain(m['relapseType']),
    text(m['quantity']),
    flag(m['attemptedSos']),
    flag(m['postSos']),
    plain(m['streakLost']),
    tags is List ? text(tags.join('; ')) : '',
    text(m['debrief']),
    plain(m['durationSeconds']),
    plain(m['days']),
    text(m['setting'] ?? m['field']),
    text(m['note']),
    extra.isEmpty ? '' : text(jsonEncode(extra)),
  ];
}

/// ISO 8601 local time with the UTC offset, e.g. 2026-10-08T18:00:00+05:30.
String isoWithOffset(DateTime value) {
  if (value.isUtc) return value.toIso8601String();
  final base = value.toIso8601String();
  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final hh = (minutes ~/ 60).toString().padLeft(2, '0');
  final mm = (minutes % 60).toString().padLeft(2, '0');
  return '$base$sign$hh:$mm';
}

/// Quotes a cell when it contains a comma, quote, CR/LF or edge whitespace.
String csvEscape(String value) {
  final needsQuotes =
      value.contains(RegExp('[",\r\n]')) || value.trim() != value;
  return needsQuotes ? '"${value.replaceAll('"', '""')}"' : value;
}

/// Escapes user-entered text and neutralises spreadsheet formulas
/// (cells starting with = + - @ tab or CR) by prefixing an apostrophe.
String csvText(String value) {
  final guarded = value.isNotEmpty && '=+-@\t\r'.contains(value[0])
      ? "'$value"
      : value;
  return csvEscape(guarded);
}
