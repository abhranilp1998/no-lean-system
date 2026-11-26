import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/dates/domain/high_risk_dates.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../support/recovery_fakes.dart';

void main() {
  final stamp = DateTime(2026, 10, 10, 12).toIso8601String();

  Map<String, dynamic> event([String id = 'e1']) => {
    'id': id,
    'type': 'pledge',
    'timestamp': stamp,
    'metadata': <String, dynamic>{},
  };

  test('backup and state versions stay at 12 and 17', () {
    expect(BackupService.currentBackupVersion, 12);
    expect(RecoveryController.stateVersion, 17);
  });

  test(
    'backup formats 1 through 12 still import and invent no dates',
    () async {
      final service = BackupService();
      for (var version = 1; version <= 12; version++) {
        final payload = <String, dynamic>{
          'version': version,
          'events': [event('v$version')],
          if (version >= 2) 'preferences': <String, dynamic>{},
        };
        final preview = service.validateBackupJson(jsonEncode(payload));
        expect(preview.eventCount, 1, reason: 'format $version');
        expect(preview.preferences?['customHighRiskDates'], isNull);
        expect(preview.preferences?['highRiskPlans'], isNull);
        expect(preview.preferences?['paydayDay'], isNull);

        final store = MemoryRecoveryStore();
        final controller = RecoveryController(
          store: store,
          relapseLock: FakeRelapseLock(),
          now: () => DateTime(2026, 11, 27, 12),
          scheduleHighRiskDateReminders: (_) async {},
          cancelHighRiskDateReminders: () async {},
        );
        await controller.load();
        await controller.mergeImportedEvents(
          preview.events,
          preferences: preview.preferences,
          restorePreferences: true,
        );
        expect(
          controller.customHighRiskDates,
          isEmpty,
          reason: 'format $version',
        );
        expect(controller.highRiskPlans, isEmpty, reason: 'format $version');
        expect(controller.paydayDay, isNull, reason: 'format $version');
        // Missing key keeps the default (on).
        expect(
          controller.highRiskDateReminders,
          isTrue,
          reason: 'format $version',
        );
      }
    },
  );

  test('a same-version backup restores dates, payday and plans', () async {
    final service = BackupService();
    final json = jsonEncode({
      'version': 12,
      'events': [event()],
      'preferences': {
        'highRiskDateReminders': false,
        'paydayDay': 28,
        'weekdayNudges': false,
        'customHighRiskDates': [
          {
            'id': 'b1',
            'name': "Asha's birthday",
            'kind': 'birthday',
            'month': 3,
            'day': 12,
          },
        ],
        'disabledBundledDateIds': ['holi'],
        'highRiskPlans': {'custom:b1:2027-03-12': 'Call Asha'},
      },
    });
    final preview = service.validateBackupJson(json);
    expect(preview.preferences?['paydayDay'], 28);
    expect(preview.preferences?['highRiskDateReminders'], isFalse);

    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(2026, 11, 27, 12),
      scheduleHighRiskDateReminders: (_) async {},
      cancelHighRiskDateReminders: () async {},
    );
    await controller.load();
    await controller.mergeImportedEvents(
      preview.events,
      preferences: preview.preferences,
      restorePreferences: true,
    );
    expect(controller.highRiskDateReminders, isFalse);
    expect(controller.paydayDay, 28);
    expect(controller.weekdayNudges, isFalse);
    expect(controller.customHighRiskDates.single.name, "Asha's birthday");
    expect(controller.disabledBundledDateIds, contains('holi'));
    expect(controller.highRiskPlans['custom:b1:2027-03-12'], 'Call Asha');
  });

  test('malformed high-risk keys do not fail a backup', () {
    final preview = BackupService().validateBackupJson(
      jsonEncode({
        'version': 12,
        'events': [event()],
        'preferences': {
          'highRiskDateReminders': 'yes',
          'paydayDay': 99,
          'customHighRiskDates': 'nope',
          'highRiskPlans': ['x'],
        },
      }),
    );
    expect(preview.eventCount, 1);
    expect(preview.preferences?['highRiskDateReminders'], isNull);
    expect(preview.preferences?['paydayDay'], isNull);
    expect(preview.preferences?['customHighRiskDates'], isNull);
    expect(preview.preferences?['highRiskPlans'], isNull);
  });

  test('an older pending-less v16 state loads without dates', () async {
    final store = MemoryRecoveryStore(
      jsonEncode({
        'stateVersion': 16,
        'events': [event()],
      }),
    );
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(2026, 11, 27, 12),
      scheduleHighRiskDateReminders: (_) async {},
      cancelHighRiskDateReminders: () async {},
    );
    await controller.load();
    expect(controller.loadStatus, RecoveryLoadStatus.ready);
    expect(controller.highRiskDateReminders, isTrue);
    expect(controller.customHighRiskDates, isEmpty);
    expect(controller.paydayDay, isNull);
    final saved = jsonDecode(store.value!) as Map<String, dynamic>;
    expect(saved['stateVersion'], 17);
  });

  test('exported backup stays on version 12 and keeps optional keys', () async {
    final controller = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(2026, 11, 27, 12),
      scheduleHighRiskDateReminders: (_) async {},
      cancelHighRiskDateReminders: () async {},
    );
    await controller.load();
    await controller.setPaydayDay(15);
    await controller.addCustomHighRiskDate(
      name: 'Exam',
      kind: CustomDateKind.exam,
      once: DateTime(2026, 12, 15),
    );
    final payload = BackupService().buildBackupPayload(
      controller.events,
      preferences: controller.portablePreferences,
    );
    expect(payload['version'], 12);
    expect(payload['preferences']['paydayDay'], 15);
    expect(payload['preferences']['customHighRiskDates'], isNotEmpty);
    final preview = BackupService().validateBackupJson(jsonEncode(payload));
    expect(preview.preferences?['paydayDay'], 15);
  });
}
