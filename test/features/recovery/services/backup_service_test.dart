import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

void main() {
  group('BackupService', () {
    late BackupService service;
    late List<RecoveryEvent> mockEvents;

    setUp(() {
      service = BackupService();
      mockEvents = [
        RecoveryEvent.create(
          type: RecoveryEventType.pledge,
          timestamp: DateTime(2023, 1, 1),
        ),
        RecoveryEvent.create(
          type: RecoveryEventType.relapse,
          timestamp: DateTime(2023, 1, 2),
        ),
      ];
    });

    test('mergeEvents combines lists and ignores duplicates based on ID', () {
      final existingEvents = [...mockEvents];
      final newEvent = RecoveryEvent.create(
        type: RecoveryEventType.craving,
        timestamp: DateTime(2023, 1, 3),
      );
      
      final importedEvents = [
        mockEvents.first, // Duplicate
        newEvent,         // New
      ];

      final merged = service.mergeEvents(existingEvents, importedEvents);

      expect(merged.length, 3);
      expect(merged.contains(newEvent), isTrue);
      
      // Should be sorted chronologically
      expect(merged[0].timestamp, DateTime(2023, 1, 1));
      expect(merged[1].timestamp, DateTime(2023, 1, 2));
      expect(merged[2].timestamp, DateTime(2023, 1, 3));
    });
  });
}
