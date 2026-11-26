import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';

import '../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(RecoveryController, MemoryRecoveryStore)> loaded([
    String? stored,
  ]) async {
    final store = MemoryRecoveryStore(stored);
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
    );
    await controller.load();
    return (controller, store);
  }

  String state(int version, [Map<String, Object?> extra = const {}]) =>
      jsonEncode({
        'stateVersion': version,
        'lastDose': DateTime(2026, 1, 1).toIso8601String(),
        'events': [
          RecoveryEvent.create(
            type: RecoveryEventType.recoveryStart,
            timestamp: DateTime(2026, 1, 1),
          ).toJson(),
        ],
        ...extra,
      });

  test('the state version is not bumped by this feature', () {
    expect(RecoveryController.stateVersion, 17);
    expect(BackupService.currentBackupVersion, 12);
  });

  test(
    'old saved state loads with both new settings at their defaults',
    () async {
      for (final version in [9, 15, 17]) {
        final (c, _) = await loaded(state(version));
        expect(c.isLoaded, isTrue, reason: 'v$version');
        expect(c.weeklyRecapNotify, isFalse);
        expect(c.reportMedicines, isEmpty);
      }
    },
  );

  test('the settings persist and come back after a reload', () async {
    final (c, store) = await loaded(state(17));
    await c.updateWeeklyRecapNotify(true);
    await c.updateReportMedicines('  sertraline 50 mg  ');
    expect(c.reportMedicines, 'sertraline 50 mg');
    final saved = jsonDecode(store.value!) as Map<String, dynamic>;
    expect(saved['weeklyRecapNotify'], isTrue);
    expect(saved['reportMedicines'], 'sertraline 50 mg');
    expect(saved['stateVersion'], 17);

    final (again, againStore) = await loaded(store.value);
    expect(again.weeklyRecapNotify, isTrue);
    expect(again.reportMedicines, 'sertraline 50 mg');

    await again.updateReportMedicines('');
    final cleared = jsonDecode(againStore.value!) as Map<String, dynamic>;
    expect(cleared['reportMedicines'], '');
  });

  test('the medicines note is capped', () async {
    final (c, _) = await loaded(state(17));
    await c.updateReportMedicines('x' * (maxReportMedicinesLength + 50));
    expect(c.reportMedicines.length, maxReportMedicinesLength);
  });

  test(
    'the recap toggle schedules and cancels the notification safely',
    () async {
      NotificationService.instance.prefs = const NotificationPrefs();
      final (c, _) = await loaded(state(17));
      // No platform plugin in tests: scheduling must fail quietly, not throw.
      await c.updateWeeklyRecapNotify(true);
      await c.updateWeeklyRecapNotify(false);
      expect(c.weeklyRecapNotify, isFalse);
    },
  );

  group('old backups still import', () {
    final pledge = {
      'id': 'p-1',
      'type': 'pledge',
      'timestamp': DateTime(2026, 1, 1, 9).toIso8601String(),
      'metadata': <String, dynamic>{},
    };

    test('a backup without the new keys imports at every format', () {
      for (var f = 1; f <= BackupService.currentBackupVersion; f++) {
        final preview = BackupService().validateBackupJson(
          jsonEncode({
            'version': f,
            'events': [pledge],
            'preferences': {'dailySpend': 100},
          }),
        );
        expect(preview.eventCount, 1, reason: 'format $f');
        expect(preview.preferences?['reportMedicines'], isNull);
      }
    });

    test('importing an old backup leaves the new settings untouched', () async {
      final (c, _) = await loaded(
        state(17, {'weeklyRecapNotify': true, 'reportMedicines': 'mine'}),
      );
      expect(c.weeklyRecapNotify, isTrue);
      final preview = BackupService().validateBackupJson(
        jsonEncode({
          'version': 11,
          'events': [pledge],
          'preferences': {'dailySpend': 250},
        }),
      );
      await c.mergeImportedEvents(
        preview.events,
        preferences: preview.preferences,
        restorePreferences: true,
        tryBiometrics: false,
      );
      expect(c.dailySpend, 250);
      expect(c.weeklyRecapNotify, isTrue);
      expect(c.reportMedicines, 'mine');
    });

    test('the medicines note round-trips through a backup', () async {
      final (c, _) = await loaded(state(17));
      await c.updateReportMedicines('sertraline 50 mg');
      expect(c.portablePreferences['reportMedicines'], 'sertraline 50 mg');
      // The recap notification is device-specific and never exported.
      await c.updateWeeklyRecapNotify(true);
      expect(c.portablePreferences.containsKey('weeklyRecapNotify'), isFalse);

      final preview = BackupService().validateBackupJson(
        jsonEncode({
          'version': 12,
          'events': [pledge],
          'preferences': c.portablePreferences,
        }),
      );
      expect(preview.preferences!['reportMedicines'], 'sertraline 50 mg');

      final (fresh, _) = await loaded(state(17));
      await fresh.mergeImportedEvents(
        preview.events,
        preferences: preview.preferences,
        restorePreferences: true,
        tryBiometrics: false,
      );
      expect(fresh.reportMedicines, 'sertraline 50 mg');
      expect(fresh.weeklyRecapNotify, isFalse);
    });

    test(
      'a backup claiming the recap notification cannot switch it on',
      () async {
        final (c, _) = await loaded(state(17));
        await c.mergeImportedEvents(
          const [],
          preferences: {'weeklyRecapNotify': true},
          restorePreferences: true,
          tryBiometrics: false,
        );
        expect(c.weeklyRecapNotify, isFalse);
      },
    );

    test('a bad medicines value is rejected, not stored', () {
      expect(
        () => BackupService().validateBackupJson(
          jsonEncode({
            'version': 12,
            'events': [pledge],
            'preferences': {'reportMedicines': 42},
          }),
        ),
        throwsFormatException,
      );
    });
  });
}
