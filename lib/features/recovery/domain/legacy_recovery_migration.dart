import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/utils/formatters.dart';
import 'craving_entry.dart';
import 'recovery_event.dart';
import 'sos_session.dart';

/// Stable IDs make repeated migration/import of the same legacy facts idempotent.
/// Day-only history stays day-only; it is never an invented timed relapse.
List<RecoveryEvent> migrateLegacyRecovery(Map<String, dynamic> map) {
  final result = <RecoveryEvent>[];
  void add(
    RecoveryEventType type,
    DateTime at,
    Map<String, dynamic> metadata,
    String identity,
  ) {
    result.add(
      RecoveryEvent.fromJson({
        'id': const Uuid().v5(Namespace.url.value, 'no-lean/legacy/$identity'),
        'type': type.name,
        'timestamp': at.toIso8601String(),
        'metadata': metadata,
      }),
    );
  }

  final cravings = map['cravings'];
  if (cravings != null && cravings is! List) {
    throw const FormatException('Invalid craving history.');
  }
  final occurrences = <String, int>{};
  for (final raw in (cravings as List? ?? [])) {
    if (raw is! Map) throw const FormatException('Invalid craving entry.');
    if (raw['createdAt'] is! String ||
        DateTime.tryParse(raw['createdAt']) == null) {
      throw const FormatException('Craving date is missing or invalid.');
    }
    final entry = CravingEntry.fromJson(Map<String, dynamic>.from(raw));
    final fingerprint = jsonEncode(entry.toJson());
    final index = occurrences.update(
      fingerprint,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    add(RecoveryEventType.craving, entry.createdAt, {
      'intensity': entry.intensity,
      'trigger': entry.trigger,
      'note': entry.note,
    }, 'craving/$fingerprint/$index');
  }
  final sessions = map['sosSessions'];
  if (sessions != null && sessions is! List) {
    throw const FormatException('Invalid SOS history.');
  }
  occurrences.clear();
  for (final raw in (sessions as List? ?? [])) {
    if (raw is! Map) throw const FormatException('Invalid SOS entry.');
    if (raw['startedAt'] is! String ||
        DateTime.tryParse(raw['startedAt']) == null) {
      throw const FormatException('SOS date is missing or invalid.');
    }
    if (raw['completedAt'] != null &&
        (raw['completedAt'] is! String ||
            DateTime.tryParse(raw['completedAt']) == null ||
            DateTime.parse(
              raw['completedAt'],
            ).isBefore(DateTime.parse(raw['startedAt'])))) {
      throw const FormatException('SOS completion is invalid.');
    }
    final session = SosSession.fromJson(Map<String, dynamic>.from(raw));
    final fingerprint = jsonEncode(session.toJson());
    final index = occurrences.update(
      fingerprint,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    add(
      RecoveryEventType.sosStart,
      session.startedAt,
      {},
      'sos/$fingerprint/$index',
    );
    final startId = result.last.id;
    if (session.completedAt != null) {
      add(RecoveryEventType.sosComplete, session.completedAt!, {
        'startId': startId,
        'debrief': ?session.debrief,
      }, 'sos-complete/$startId');
    }
  }
  final days = map['cleanDays'];
  if (days != null && days is! Map) {
    throw const FormatException('Invalid day history.');
  }
  for (final entry in (days as Map? ?? {}).entries) {
    final date = DateTime.tryParse(entry.key.toString());
    if (date == null || entry.value is! bool || dateKey(date) != entry.key) {
      throw const FormatException('Invalid day history entry.');
    }
    add(RecoveryEventType.daySummary, date, {
      'date': entry.key,
      'clean': entry.value,
      'source': 'legacy',
    }, 'day/${entry.key}/${entry.value}');
  }
  if (map['lastDose'] != null &&
      (map['lastDose'] is! String ||
          DateTime.tryParse(map['lastDose']) == null)) {
    throw const FormatException('Invalid lastDose date.');
  }
  final baseline = DateTime.tryParse(map['lastDose'] as String? ?? '');
  if (baseline != null) {
    add(RecoveryEventType.recoveryStart, baseline, {
      'source': 'legacyLastDose',
    }, 'baseline/${baseline.toIso8601String()}');
  }
  if (map['lastPledge'] != null &&
      (map['lastPledge'] is! String ||
          DateTime.tryParse(map['lastPledge']) == null)) {
    throw const FormatException('Invalid lastPledge date.');
  }
  final pledge = DateTime.tryParse(map['lastPledge'] as String? ?? '');
  if (pledge != null) {
    add(RecoveryEventType.pledge, pledge, {
      'source': 'legacyLastPledge',
    }, 'pledge/${pledge.toIso8601String()}');
  }
  final longest = map['longestStreak'] ?? map['longestStreakDays'];
  if (longest is num && longest.isFinite && longest > 0) {
    add(RecoveryEventType.milestone, baseline ?? pledge ?? DateTime(2000), {
      'days': longest.round(),
      'source': 'legacyLongestStreak',
    }, 'longest/$longest');
  }
  return result;
}

Map<String, dynamic> legacyExportPreferences(Map<String, dynamic> map) {
  final settings = map['settings'] is Map
      ? Map<String, dynamic>.from(map['settings'])
      : <String, dynamic>{};
  return {
    ...map,
    ...settings,
    if (settings.containsKey('soundEffectsEnabled'))
      'soundscape': settings['soundEffectsEnabled'],
    if (settings.containsKey('vibrationEnabled'))
      'hapticFeedback': settings['vibrationEnabled'],
    if (settings.containsKey('soundEffect'))
      'feedbackSound': settings['soundEffect'],
    if (settings.containsKey('effectIntensity'))
      'intensity': settings['effectIntensity'],
  }..remove('pin');
}
