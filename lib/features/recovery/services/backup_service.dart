import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/feedback_preferences.dart';
import '../domain/effect_intensity.dart';
import '../domain/recovery_event.dart';

class BackupPreview {
  const BackupPreview({
    required this.eventCount,
    required this.oldestEventDate,
    required this.newestEventDate,
    required this.events,
    required this.preferences,
  });

  final int eventCount;
  final DateTime? oldestEventDate;
  final DateTime? newestEventDate;
  final List<RecoveryEvent> events;
  final Map<String, dynamic>? preferences;

  bool get hasPreferences => preferences != null && preferences!.isNotEmpty;
}

class BackupService {
  static const int currentBackupVersion = 2;
  static const int maxBackupBytes = 5 * 1024 * 1024;
  static const int maxEventCount = 50000;

  Future<void> exportBackup(
    List<RecoveryEvent> events, {
    required Map<String, dynamic> preferences,
  }) async {
    final payload = {
      'version': currentBackupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'events': events.map((event) => event.toJson()).toList(),
      'preferences': preferences,
      'excludedSecureData': const ['relapsePin', 'trustedContact'],
    };

    final jsonString = jsonEncode(payload);
    if (utf8.encode(jsonString).length > maxBackupBytes) {
      throw const FormatException(
        'Backup is larger than the 5 MB safety limit.',
      );
    }
    final fileName =
        'nolean_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      try {
        await file.writeAsString(jsonString, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            text: 'NO LEAN recovery backup',
          ),
        );
      } finally {
        if (await file.exists()) await file.delete();
      }
    } else {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save Backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path != null) {
        await File(path).writeAsString(jsonString, flush: true);
      }
    }
  }

  Future<BackupPreview?> pickAndValidateBackup() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
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
      content = utf8.decode(bytes);
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
      final map = Map<String, dynamic>.from(decoded);
      final version = map['version'];
      if (version is! int || version < 1 || version > currentBackupVersion) {
        throw FormatException('Unsupported backup version: $version');
      }

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
        events.add(event);
      }
      events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final preferences = version >= 2
          ? _validatePreferences(map['preferences'])
          : null;
      return BackupPreview(
        eventCount: events.length,
        oldestEventDate: events.firstOrNull?.timestamp,
        newestEventDate: events.lastOrNull?.timestamp,
        events: events,
        preferences: preferences,
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
      'soundscape',
      'hapticFeedback',
    ]) {
      final value = input[key];
      if (value != null && value is! bool) {
        throw FormatException('$key must be true or false.');
      }
    }
    for (final key in ['feedbackSound', 'intensity']) {
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

    final reasons = stringList('reasons');
    final reminders = stringList('reminderMessages');
    final preferences = <String, dynamic>{};
    if (dailySpend != null) preferences['dailySpend'] = dailySpend;
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
      'soundscape',
      'hapticFeedback',
      'feedbackSound',
      'intensity',
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
