import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import '../domain/recovery_event.dart';

class BackupPreview {
  const BackupPreview({
    required this.eventCount,
    required this.oldestEventDate,
    required this.newestEventDate,
    required this.events,
  });

  final int eventCount;
  final DateTime? oldestEventDate;
  final DateTime? newestEventDate;
  final List<RecoveryEvent> events;
}

class BackupService {
  static const int currentBackupVersion = 1;

  Future<void> exportBackup(List<RecoveryEvent> events) async {
    final payload = {
      'version': currentBackupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'events': events.map((e) => e.toJson()).toList(),
    };

    final jsonString = jsonEncode(payload);
    final fileName = 'nolean_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonString);
      
      final xFile = XFile(file.path, mimeType: 'application/json');
      await Share.shareXFiles([xFile], text: 'NO LEAN Recovery Backup');
    } else {
      // Fallback for desktop using file_picker if we need it
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save Backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path != null) {
        final file = File(path);
        await file.writeAsString(jsonString);
      }
    }
  }

  Future<BackupPreview?> pickAndValidateBackup() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    String content;

    if (kIsWeb || file.path == null) {
      if (file.bytes == null) throw Exception('Cannot read file contents.');
      content = utf8.decode(file.bytes!);
    } else {
      content = await File(file.path!).readAsString();
    }

    return _validateBackupJson(content);
  }

  BackupPreview _validateBackupJson(String jsonString) {
    try {
      final map = jsonDecode(jsonString);
      if (map is! Map<String, dynamic>) {
        throw const FormatException('Invalid backup format: Not a JSON object');
      }

      final version = map['version'] as int?;
      if (version != currentBackupVersion) {
        throw FormatException('Unsupported backup version: $version');
      }

      final eventsList = map['events'];
      if (eventsList is! List) {
        throw const FormatException('Invalid backup format: Missing events list');
      }

      final events = eventsList
          .whereType<Map>()
          .map((item) => RecoveryEvent.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return BackupPreview(
        eventCount: events.length,
        oldestEventDate: events.firstOrNull?.timestamp,
        newestEventDate: events.lastOrNull?.timestamp,
        events: events,
      );
    } catch (e) {
      throw FormatException('Failed to parse backup file: $e');
    }
  }

  List<RecoveryEvent> mergeEvents(
    List<RecoveryEvent> existingEvents,
    List<RecoveryEvent> importedEvents,
  ) {
    final existingIds = existingEvents.map((e) => e.id).toSet();
    final newEvents = importedEvents.where((e) => !existingIds.contains(e.id));
    
    final merged = [...existingEvents, ...newEvents];
    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    
    return merged;
  }
}
