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
        metadata: {'intensity': 5, 'trigger': 'Other', 'note': ''},
      );

      final importedEvents = [
        mockEvents.first, // Duplicate
        newEvent, // New
      ];

      final merged = service.mergeEvents(existingEvents, importedEvents);

      expect(merged.length, 3);
      expect(merged.contains(newEvent), isTrue);

      // Should be sorted chronologically
      expect(merged[0].timestamp, DateTime(2023, 1, 1));
      expect(merged[1].timestamp, DateTime(2023, 1, 2));
      expect(merged[2].timestamp, DateTime(2023, 1, 3));
    });

    test(
      'version 2 restores validated personalization but excludes secrets',
      () {
        final preview = service.validateBackupJson(
          jsonEncode({
            'version': 2,
            'events': mockEvents.map((event) => event.toJson()).toList(),
            'preferences': {
              'dailySpend': 450,
              'reasons': ['Clarity'],
              'riskWindow': {'startMinutes': 1020, 'endMinutes': 1200},
              'cooldownMinutes': 20,
              'riskReminders': false,
              'peakHourLock': true,
              'dashboardNoticeStyle': 'statusStack',
              'relapsePin': '1234',
              'trustedContact': {'phone': '5551234567'},
            },
          }),
        );

        expect(preview.hasPreferences, isTrue);
        expect(preview.preferences!['dailySpend'], 450);
        expect(preview.preferences!['cooldownMinutes'], 20);
        expect(preview.preferences!['peakHourLock'], isTrue);
        expect(preview.preferences!['dashboardNoticeStyle'], 'statusStack');
        expect(preview.preferences, isNot(contains('relapsePin')));
        expect(preview.preferences, isNot(contains('trustedContact')));
      },
    );

    test('rejects duplicate IDs inside one backup', () {
      final duplicate = mockEvents.first.toJson();
      expect(
        () => service.validateBackupJson(
          jsonEncode({
            'version': 2,
            'events': [duplicate, duplicate],
            'preferences': <String, dynamic>{},
          }),
        ),
        throwsFormatException,
      );
    });

    test(
      'rejects malformed list entries instead of silently dropping them',
      () {
        expect(
          () => service.validateBackupJson(
            jsonEncode({
              'version': 1,
              'events': [mockEvents.first.toJson(), 'not-an-event'],
            }),
          ),
          throwsFormatException,
        );
      },
    );

    test('rejects unsupported or out-of-range customizations', () {
      expect(
        () => service.validateBackupJson(
          jsonEncode({
            'version': 2,
            'events': <Object>[],
            'preferences': {
              'cooldownMinutes': 0,
              'feedbackSound': 'unknownSound',
            },
          }),
        ),
        throwsFormatException,
      );
    });

    group('tolerant import', () {
      String backup() => jsonEncode({
        'version': 1,
        'events': mockEvents.map((event) => event.toJson()).toList(),
      });

      test('accepts a UTF-8 BOM and surrounding whitespace', () {
        final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('\n  ${backup()}  \n')];
        final text = BackupService.decodeBackupBytes(bytes);
        expect(service.validateBackupJson(text).events.length, 2);
      });

      test('accepts UTF-16 LE and BE files with a BOM', () {
        final units = backup().codeUnits;
        final le = [
          0xFF,
          0xFE,
          for (final u in units) ...[u & 0xFF, u >> 8],
        ];
        final be = [
          0xFE,
          0xFF,
          for (final u in units) ...[u >> 8, u & 0xFF],
        ];
        for (final bytes in [le, be]) {
          final text = BackupService.decodeBackupBytes(bytes);
          expect(service.validateBackupJson(text).events.length, 2);
        }
      });

      test('accepts share text wrapped around the JSON', () {
        final text = 'NO LEAN backup\n${backup()}\nSent from my phone';
        expect(service.validateBackupJson(text).events.length, 2);
      });

      test('gives a plain message for files that are not backups', () {
        expect(
          () =>
              service.validateBackupJson('Thought you might find this useful'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('not a NO LEAN backup'),
            ),
          ),
        );
        expect(
          () => service.validateBackupJson('{"version": 1, "events": [}'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('damaged'),
            ),
          ),
        );
      });
    });
  });
}
