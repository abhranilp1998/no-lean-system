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
import 'android_document_export.dart';

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

/// Writes an export somewhere the user picks. Returns `true` when the file
/// was written and `false` when the user cancelled.
typedef ExportSaver =
    Future<bool> Function(
      String content, {
      required String fileName,
      required String mimeType,
      required String extension,
    });

class BackupService {
  BackupService({
    ExportSaver? saver,
    Future<Directory> Function()? temporaryDirectory,
    Future<ShareResult> Function(ShareParams)? share,
  }) : _saver = saver,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _share = share ?? SharePlus.instance.share;

  final ExportSaver? _saver;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<ShareResult> Function(ShareParams) _share;
  static int _exportSequence = 0;

  /// Format 4 adds `zones`; format 5 adds `codeSession` events; format 6 adds
  /// `zoneEntry` events; format 7 adds `cravingCheck` events, structured
  /// dose/cost/stress metadata and the `bottleMl` preference. Older formats
  /// still import (format 6 and older convert explicit volumes/counts while
  /// bottle-only notes keep their unknown volume); older apps refuse newer formats instead of
  /// failing per event. Format 8 adds `appUnlock` events (app lock exit
  /// plan); the app-lock policy itself is device-specific and never exported.
  static const int currentBackupVersion = 8;
  static const int maxBackupBytes = 5 * 1024 * 1024;
  static const int maxEventCount = 50000;

  /// Returns `true` when the backup was saved, `false` if the user cancelled.
  Future<bool> exportBackup(
    List<RecoveryEvent> events, {
    required Map<String, dynamic> preferences,
    List<DangerZone> zones = const [],
  }) {
    return exportJson(
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

  /// Returns `true` when saved, `false` if the user cancelled the Save
  /// screen. Set [enforceSizeLimit] to false for the emergency export of
  /// preserved copies, which must never be blocked by the import limit.
  Future<bool> exportJson(String jsonString, {bool enforceSizeLimit = true}) {
    if (enforceSizeLimit && utf8.encode(jsonString).length > maxBackupBytes) {
      throw const FormatException(
        'Backup is larger than the 5 MB safety limit.',
      );
    }
    return _shareText(
      jsonString,
      fileName: 'nolean_backup_${_stamp()}.json',
      mimeType: 'application/json',
      extension: 'json',
    );
  }

  /// Shares every event as CSV (a readable copy; JSON stays the restorable
  /// backup format).
  Future<bool> exportEventsCsv(List<RecoveryEvent> events) => _shareText(
    buildEventsCsv(events),
    fileName: 'nolean_history_${_stamp()}.csv',
    mimeType: 'text/csv',
    extension: 'csv',
  );

  String _stamp() =>
      '${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}_${_exportSequence++}';

  Future<bool> _shareText(
    String content, {
    required String fileName,
    required String mimeType,
    required String extension,
  }) {
    final saver = _saver;
    if (saver != null) {
      return saver(
        content,
        fileName: fileName,
        mimeType: mimeType,
        extension: extension,
      );
    }
    return _saveWithSystemScreen(
      content,
      fileName: fileName,
      mimeType: mimeType,
      extension: extension,
    );
  }

  Future<bool> _saveWithSystemScreen(
    String content, {
    required String fileName,
    required String mimeType,
    required String extension,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      return const AndroidDocumentExport().save(
        content,
        fileName: fileName,
        mimeType: mimeType,
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      // Save straight to a location the user picks (Downloads, Drive, ...)
      // with the iOS document picker.
      // A null result means the user cancelled. Android uses a verified
      // document write above rather than relying on the picker's URI alone.
      final bytes = Uint8List.fromList(utf8.encode(content));
      try {
        final path = await FilePicker.saveFile(
          dialogTitle: 'Save export',
          fileName: fileName,
          type: FileType.any,
          bytes: bytes,
        );
        return path != null;
      } on UnimplementedError {
        // Fall through to sharing on platforms without a save screen.
      } on UnsupportedError {
        // Same.
      }
      await _shareFile(content, fileName: fileName, mimeType: mimeType);
      return true;
    }
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save export',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (path == null) return false;
    await File(path).writeAsString(content, flush: true);
    return true;
  }

  /// Shares a copy without deleting it right away: the receiving app may
  /// read it after the share sheet closes. Older shared exports are cleaned
  /// up on the next share instead.
  Future<void> _shareFile(
    String content, {
    required String fileName,
    required String mimeType,
  }) async {
    final root = await _temporaryDirectory();
    final dir = Directory('${root.path}/exports');
    if (await dir.exists()) {
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      await for (final entity in dir.list()) {
        if (entity is File && (await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } else {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content, flush: true);
    await _share(ShareParams(files: [XFile(file.path, mimeType: mimeType)]));
  }

  /// Shares an export through the share sheet (for sending to a chat or
  /// email instead of saving).
  Future<void> shareBackupJson(String jsonString) => _shareFile(
    jsonString,
    fileName: 'nolean_backup_${_stamp()}.json',
    mimeType: 'application/json',
  );

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

    final List<int> bytes;
    if (kIsWeb || file.path == null) {
      final data = file.bytes;
      if (data == null) {
        throw const FormatException('Cannot read backup data.');
      }
      bytes = data;
    } else {
      bytes = await File(file.path!).readAsBytes();
    }
    return validateBackupJson(decodeBackupBytes(bytes));
  }

  /// Decodes backup bytes written by any app version or re-saved by another
  /// app: UTF-8 with or without a BOM, or UTF-16 LE/BE with a BOM (some
  /// Android editors save that way).
  @visibleForTesting
  static String decodeBackupBytes(List<int> bytes) {
    if (bytes.length >= 2) {
      final b0 = bytes[0], b1 = bytes[1];
      final isLe = b0 == 0xFF && b1 == 0xFE;
      final isBe = b0 == 0xFE && b1 == 0xFF;
      if (isLe || isBe) {
        if (bytes.length.isOdd) {
          throw const FormatException(
            'This file has damaged text encoding. Export a new .json backup.',
          );
        }
        final units = <int>[];
        for (var i = 2; i + 1 < bytes.length; i += 2) {
          units.add(
            isLe
                ? bytes[i] | (bytes[i + 1] << 8)
                : (bytes[i] << 8) | bytes[i + 1],
          );
        }
        for (var index = 0; index < units.length; index++) {
          final unit = units[index];
          if (unit >= 0xD800 && unit <= 0xDBFF) {
            index++;
            if (index == units.length ||
                units[index] < 0xDC00 ||
                units[index] > 0xDFFF) {
              throw const FormatException(
                'This file has damaged text encoding. Export a new .json backup.',
              );
            }
          } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
            throw const FormatException(
              'This file has damaged text encoding. Export a new .json backup.',
            );
          }
        }
        return String.fromCharCodes(units);
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const FormatException(
        'This file has damaged text encoding. Export a new .json backup.',
      );
    }
  }

  /// Strips things that commonly wrap an otherwise valid backup: a byte-order
  /// mark, whitespace or NUL padding, or text a share target added before or
  /// after the JSON object.
  @visibleForTesting
  static String normalizeBackupText(String raw) {
    // Padding belongs outside the JSON. Removing it everywhere would silently
    // change valid U+FEFF characters inside a recorded note or preference.
    bool isPadding(int index) =>
        raw[index] == '\u0000' || raw[index].trim().isEmpty;
    var startPadding = 0;
    var endPadding = raw.length;
    while (startPadding < endPadding && isPadding(startPadding)) {
      startPadding++;
    }
    while (endPadding > startPadding && isPadding(endPadding - 1)) {
      endPadding--;
    }
    var text = raw.substring(startPadding, endPadding);
    if (text.isEmpty) {
      throw const FormatException(
        'This file is empty. Export a new backup and save it to Downloads.',
      );
    }
    if (text == 'NO LEAN recovery backup' || text == 'NO LEAN history (CSV)') {
      throw const FormatException(
        'This file contains only the share message. Export a new backup '
        'and save the .json attachment to Downloads.',
      );
    }
    if (text.startsWith('{') && text.endsWith('}')) return text;
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException(
        'This file is not a NO LEAN backup. Pick the .json file from '
        'Export backup.',
      );
    }
    return text.substring(start, end + 1);
  }

  @visibleForTesting
  BackupPreview validateBackupJson(String rawJson) {
    final jsonString = normalizeBackupText(rawJson);
    if (utf8.encode(jsonString).length > maxBackupBytes) {
      throw const FormatException('Backup exceeds the 5 MB safety limit.');
    }

    try {
      final Object? decoded;
      try {
        decoded = jsonDecode(jsonString);
      } on FormatException {
        throw const FormatException(
          'This file is damaged or not a NO LEAN backup. Pick the .json file '
          'from Export backup.',
        );
      }
      if (decoded is! Map) {
        throw const FormatException('Backup must be a JSON object.');
      }
      var map = Map<String, dynamic>.from(decoded);
      var upgradeQuantities = false;
      if (!map.containsKey('version') && map['stateVersion'] is int) {
        final stateVersion = map['stateVersion'] as int;
        upgradeQuantities = stateVersion < 12;
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
      // Convert only quantities whose units establish the volume/count.
      // Legacy bottle notes stay text: no historical size was recorded.
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
        events.add(upgradeQuantities ? upgradeEventQuantity(event) : event);
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
