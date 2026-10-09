import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/feedback_preferences.dart';
import '../../dashboard/domain/dashboard_notice_style.dart';
import '../application/recovery_controller.dart';
import '../domain/dose_units.dart';
import '../domain/effect_intensity.dart';
import '../domain/events_csv.dart';
import '../domain/legacy_recovery_migration.dart';
import '../domain/quantity_upgrade.dart';
import '../domain/recovery_event.dart';
import '../../zones/domain/danger_zone.dart';

class BackupPreview {
  const BackupPreview({
    required this.eventCount,
    required this.oldestEventDate,
    required this.newestEventDate,
    required this.events,
    required this.preferences,
    this.zones = const [],
  });

  final int eventCount;
  final DateTime? oldestEventDate;
  final DateTime? newestEventDate;
  final List<RecoveryEvent> events;
  final Map<String, dynamic>? preferences;

  /// Danger zones (backup format 4+). Merged by ID on import.
  final List<DangerZone> zones;

  bool get hasPreferences => preferences != null && preferences!.isNotEmpty;
}

class BackupService {
  /// Format 4 adds `zones`; format 5 adds `codeSession` events; format 6 adds
  /// `zoneEntry` events; format 7 adds `cravingCheck` events, structured
  /// dose/cost/stress metadata and the `bottleMl` preference. Older formats
  /// still import (format 6 and older get exact free-text quantities
  /// converted, text kept); older apps refuse newer formats instead of
  /// failing per event.
  static const int currentBackupVersion = 7;
  static const int maxBackupBytes = 5 * 1024 * 1024;
  static const int maxEventCount = 50000;

  Future<void> exportBackup(
    List<RecoveryEvent> events, {
    required Map<String, dynamic> preferences,
    List<DangerZone> zones = const [],
  }) async {
    await exportJson(
      jsonEncode(
        buildBackupPayload(events, preferences: preferences, zones: zones),
      ),
    );
  }

  @visibleForTesting
  Map<String, dynamic> buildBackupPayload(
    List<RecoveryEvent> events, {
    required Map<String, dynamic> preferences,
    List<DangerZone> zones = const [],
  }) {
    return {
      'version': currentBackupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'events': events.map((event) => event.toJson()).toList(),
      'zones': zones.map((zone) => zone.toJson()).toList(),
      'preferences': preferences,
      'excludedSecureData': const ['relapsePin', 'trustedContact'],
    };
  }

  Future<void> exportJson(String jsonString) async {
    if (utf8.encode(jsonString).length > maxBackupBytes) {
      throw const FormatException(
        'Backup is larger than the 5 MB safety limit.',
      );
    }
    await _shareText(
      jsonString,
      fileName: 'nolean_backup_${_stamp()}.json',
      mimeType: 'application/json',
      extension: 'json',
      shareText: 'NO LEAN recovery backup',
    );
  }

  /// Shares every event as CSV (a readable copy; JSON stays the restorable
  /// backup format).
  Future<void> exportEventsCsv(List<RecoveryEvent> events) => _shareText(
    buildEventsCsv(events),
    fileName: 'nolean_history_${_stamp()}.csv',
    mimeType: 'text/csv',
    extension: 'csv',
    shareText: 'NO LEAN history (CSV)',
  );

  String _stamp() => DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

  Future<void> _shareText(
    String content, {
    required String fileName,
    required String mimeType,
    required String extension,
    required String shareText,
  }) async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      try {
        await file.writeAsString(content, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: mimeType)],
            text: shareText,
          ),
        );
      } finally {
        if (await file.exists()) await file.delete();
      }
    } else {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save export',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
      if (path != null) {
        await File(path).writeAsString(content, flush: true);
      }
    }
  }

  Future<BackupPreview?> pickAndValidateBackup() async {
    // Android's picker filters custom extensions by MIME type. Backups that
    // went through Drive, WhatsApp, Telegram or Downloads often come back as
    // application/octet-stream or text/plain and show up greyed out, so on
    // mobile we allow any file and rely on validateBackupJson instead.
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    final result = await FilePicker.pickFiles(
      type: isMobile ? FileType.any : FileType.custom,
      allowedExtensions: isMobile ? null : const ['json'],
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    if (file.size > maxBackupBytes) {
      throw const FormatException('Backup exceeds the 5 MB safety limit.');
    }

    final String content;
    if (kIsWeb || file.path == null) {
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('Cannot read backup data.');
      }
      content = utf8.decode(bytes, allowMalformed: false);
    } else {
      content = await File(file.path!).readAsString();
    }
    return validateBackupJson(content);
  }

  @visibleForTesting
  BackupPreview validateBackupJson(String jsonString) {
    if (utf8.encode(jsonString).length > maxBackupBytes) {
      throw const FormatException('Backup exceeds the 5 MB safety limit.');
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        throw const FormatException('Backup must be a JSON object.');
      }
      var map = Map<String, dynamic>.from(decoded);
      var upgradeQuantities = false;
      var upgradeBottleMl = defaultBottleMl;
      if (!map.containsKey('version') && map['stateVersion'] is int) {
        final stateVersion = map['stateVersion'] as int;
        upgradeQuantities = stateVersion < 12;
        final stateBottle = map['bottleMl'];
        if (stateBottle is num && isValidBottleMl(stateBottle)) {
          upgradeBottleMl = stateBottle.toDouble();
        }
        if (stateVersion < 2 ||
            stateVersion > RecoveryController.stateVersion) {
          throw FormatException(
            'Unsupported recovery state version: $stateVersion',
          );
        }
        map = {
          'version': currentBackupVersion,
          'events': stateVersion < 6
              ? migrateLegacyRecovery(map).map((e) => e.toJson()).toList()
              : map['events'],
          'preferences': legacyExportPreferences(map),
          if (map['zones'] != null) 'zones': map['zones'],
        };
      }
      final version = map['version'];
      if (version is! int || version < 1 || version > currentBackupVersion) {
        throw FormatException('Unsupported backup version: $version');
      }
      // Older backups have no bottle size: "2 bottles" uses the 100 ml
      // default, exactly like the v11 -> v12 state migration.
      if (version <= 6) upgradeQuantities = true;

      final rawEvents = map['events'];
      if (rawEvents is! List) {
        throw const FormatException('Backup is missing its events list.');
      }
      if (rawEvents.length > maxEventCount) {
        throw const FormatException('Backup contains too many events.');
      }

      final ids = <String>{};
      final nowLimit = DateTime.now().add(const Duration(days: 1));
      final earliest = DateTime.utc(2000);
      final events = <RecoveryEvent>[];
      for (final rawEvent in rawEvents) {
        if (rawEvent is! Map) {
          throw const FormatException('Every event must be a JSON object.');
        }
        final event = RecoveryEvent.fromJson(
          Map<String, dynamic>.from(rawEvent),
        );
        if (!ids.add(event.id)) {
          throw FormatException('Duplicate event ID: ${event.id}');
        }
        final timestamp = event.timestamp.toUtc();
        if (timestamp.isBefore(earliest) ||
            timestamp.isAfter(nowLimit.toUtc())) {
          throw const FormatException(
            'Event timestamp is outside the supported range.',
          );
        }
        events.add(
          upgradeQuantities
              ? upgradeEventQuantity(event, bottleMl: upgradeBottleMl)
              : event,
        );
      }
      events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final preferences = version >= 2
          ? _validatePreferences(map['preferences'])
          : null;
      final zones = version >= 4 || map['zones'] != null
          ? DangerZone.decodeList(map['zones'])
          : const <DangerZone>[];
      return BackupPreview(
        eventCount: events.length,
        oldestEventDate: events.firstOrNull?.timestamp,
        newestEventDate: events.lastOrNull?.timestamp,
        events: events,
        preferences: preferences,
        zones: zones,
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Failed to parse backup: $error');
    }
  }

  Map<String, dynamic>? _validatePreferences(Object? rawPreferences) {
    if (rawPreferences == null) return null;
    if (rawPreferences is! Map) {
      throw const FormatException('Backup preferences must be a JSON object.');
    }
    final input = Map<String, dynamic>.from(rawPreferences);

    List<String>? stringList(String key) {
      final value = input[key];
      if (value == null) return null;
      if (value is! List ||
          value.length > 100 ||
          value.any((item) => item is! String)) {
        throw FormatException('$key must be a list of at most 100 text items.');
      }
      final result = value.cast<String>().map((item) => item.trim()).toList();
      if (result.any((item) => item.length > 500)) {
        throw FormatException(
          '$key contains an item longer than 500 characters.',
        );
      }
      return result;
    }

    final dailySpend = input['dailySpend'];
    if (dailySpend != null &&
        (dailySpend is! num || !dailySpend.isFinite || dailySpend < 0)) {
      throw const FormatException('dailySpend must be a non-negative number.');
    }
    final bottleMl = input['bottleMl'];
    if (bottleMl != null && (bottleMl is! num || !isValidBottleMl(bottleMl))) {
      throw const FormatException('bottleMl must be 10-2000 ml.');
    }
    final riskWindow = input['riskWindow'];
    if (riskWindow != null) {
      if (riskWindow is! Map ||
          riskWindow['startMinutes'] is! int ||
          riskWindow['endMinutes'] is! int ||
          (riskWindow['startMinutes'] as int) < 0 ||
          (riskWindow['startMinutes'] as int) >= 1440 ||
          (riskWindow['endMinutes'] as int) < 0 ||
          (riskWindow['endMinutes'] as int) >= 1440) {
        throw const FormatException('riskWindow is invalid.');
      }
    }
    for (final key in ['postSosWindowMinutes', 'cooldownMinutes']) {
      final value = input[key];
      if (value != null && value is! num) {
        throw FormatException('$key must be a number.');
      }
    }
    final postSosWindowMinutes = input['postSosWindowMinutes'];
    if (postSosWindowMinutes is num &&
        (postSosWindowMinutes < 15 || postSosWindowMinutes > 360)) {
      throw const FormatException(
        'postSosWindowMinutes must be between 15 and 360.',
      );
    }
    final cooldownMinutes = input['cooldownMinutes'];
    if (cooldownMinutes is num &&
        (cooldownMinutes < 1 || cooldownMinutes > 120)) {
      throw const FormatException('cooldownMinutes must be between 1 and 120.');
    }
    for (final key in [
      'scanlines',
      'reduceMotion',
      'highContrast',
      'riskReminders',
      'peakHourLock',
      'soundscape',
      'hapticFeedback',
    ]) {
      final value = input[key];
      if (value != null && value is! bool) {
        throw FormatException('$key must be true or false.');
      }
    }
    for (final key in ['feedbackSound', 'intensity', 'dashboardNoticeStyle']) {
      final value = input[key];
      if (value != null && value is! String) {
        throw FormatException('$key must be text.');
      }
    }
    final feedbackSound = input['feedbackSound'];
    if (feedbackSound is String &&
        !FeedbackSoundEffect.values.any(
          (value) => value.name == feedbackSound,
        )) {
      throw const FormatException('feedbackSound is not supported.');
    }
    final intensity = input['intensity'];
    if (intensity is String &&
        !EffectIntensity.values.any((value) => value.name == intensity)) {
      throw const FormatException('intensity is not supported.');
    }
    final dashboardNoticeStyle = input['dashboardNoticeStyle'];
    if (dashboardNoticeStyle is String &&
        !DashboardNoticeStyle.values.any(
          (value) => value.name == dashboardNoticeStyle,
        )) {
      throw const FormatException('dashboardNoticeStyle is not supported.');
    }

    final reasons = stringList('reasons');
    final reminders = stringList('reminderMessages');
    final preferences = <String, dynamic>{};
    if (dailySpend != null) preferences['dailySpend'] = dailySpend;
    if (bottleMl != null) preferences['bottleMl'] = bottleMl;
    if (reasons != null) preferences['reasons'] = reasons;
    if (reminders != null) preferences['reminderMessages'] = reminders;
    if (riskWindow != null) {
      preferences['riskWindow'] = Map<String, dynamic>.from(riskWindow as Map);
    }
    for (final key in [
      'postSosWindowMinutes',
      'cooldownMinutes',
      'scanlines',
      'reduceMotion',
      'highContrast',
      'riskReminders',
      'peakHourLock',
      'soundscape',
      'hapticFeedback',
      'feedbackSound',
      'intensity',
      'dashboardNoticeStyle',
    ]) {
      if (input.containsKey(key)) preferences[key] = input[key];
    }
    return preferences;
  }

  List<RecoveryEvent> mergeEvents(
    List<RecoveryEvent> existingEvents,
    List<RecoveryEvent> importedEvents,
  ) {
    final ids = existingEvents.map((event) => event.id).toSet();
    final merged = [...existingEvents];
    for (final event in importedEvents) {
      if (ids.add(event.id)) merged.add(event);
    }
    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged;
  }
}
