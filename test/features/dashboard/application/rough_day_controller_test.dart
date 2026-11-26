import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/dashboard/domain/rough_day.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/event_derived_state.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late RecoveryController c;
  late MemoryRecoveryStore store;
  late List<DateTime> reminders;
  late int cancels;

  Future<void> setUpController({String? stored}) async {
    now = DateTime.now();
    reminders = [];
    cancels = 0;
    store = MemoryRecoveryStore(stored);
    c = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
      scheduleUseCheck: (_) async => true,
      cancelUseCheck: () async {},
      scheduleLogLater: (at) async {
        reminders.add(at);
        return true;
      },
      cancelLogLater: () async => cancels++,
    );
    await c.load();
  }

  RelapseLogEntry entry(
    DateTime at, {
    RelapseType type = RelapseType.fullLean,
  }) => RelapseLogEntry(
    occurredAt: at,
    type: type,
    note: 'Writing this down honestly.',
    attemptedSos: false,
  );

  setUp(() => setUpController());

  group('entering and leaving', () {
    test('I am struggling opens a 24-hour rough day', () async {
      expect(c.isRoughDay, isFalse);
      await c.enterRoughDay(source: RoughDaySource.struggling);
      expect(c.isRoughDay, isTrue);
      expect(c.roughDaySource, RoughDaySource.struggling);
      expect(c.roughDayUntil, now.add(const Duration(hours: 24)));
      now = now.add(const Duration(hours: 23, minutes: 59));
      expect(c.isRoughDay, isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(c.isRoughDay, isFalse);
    });

    test('Back to normal view leaves early and cancels a reminder', () async {
      await c.enterRoughDay(source: RoughDaySource.struggling);
      await c.remindToLogLater();
      expect(reminders, isNotEmpty);
      await c.clearRoughDay();
      expect(c.isRoughDay, isFalse);
      expect(c.roughDayUntil, isNull);
      expect(cancels, greaterThan(0));
    });

    test('a fresh slip opens a rough day; a 3-day-old one does not', () async {
      await c.recordRelapse(
        entries: [entry(now.subtract(const Duration(hours: 2)))],
      );
      expect(c.isRoughDay, isTrue);
      expect(c.roughDaySource, RoughDaySource.slip);

      await c.clearRoughDay();
      await c.recordRelapse(
        entries: [entry(now.subtract(const Duration(hours: 30)))],
      );
      expect(c.isRoughDay, isFalse);
    });

    test(
      'a benzo-only slip opens a rough day but never resets lean time',
      () async {
        final before = c.lastDose;
        await c.recordRelapse(
          entries: [
            entry(
              now.subtract(const Duration(hours: 1)),
              type: RelapseType.benzo,
            ),
          ],
        );
        expect(c.isRoughDay, isTrue);
        expect(c.lastDose, before);
        final e = c.events.lastWhere(
          (e) => e.type == RecoveryEventType.relapse,
        );
        expect(resetsLeanCleanTimer(e), isFalse);
      },
    );

    test('the one-tap I used path also opens a rough day', () async {
      await c.quickLogUsed();
      expect(c.isRoughDay, isTrue);
    });

    test('survives a restart from the saved state', () async {
      await c.enterRoughDay(source: RoughDaySource.struggling);
      expect(store.value, isNotNull);
      final restarted = RecoveryController(
        store: MemoryRecoveryStore(store.value),
        relapseLock: FakeRelapseLock(),
        now: () => now.add(const Duration(hours: 3)),
      );
      await restarted.load();
      expect(restarted.isRoughDay, isTrue);
      expect(restarted.roughDaySource, RoughDaySource.struggling);
    });

    test('the log-later nudge is deferred past quiet hours', () async {
      const prefs = NotificationPrefs(
        quietHoursEnabled: true,
        quietHours: RiskWindow(startMinutes: 22 * 60, endMinutes: 7 * 60),
      );
      c.notificationPrefs = prefs;
      final at = await c.remindToLogLater();
      expect(at, deferPastQuietHours(prefs, now.add(logLaterDelay)));
      expect(reminders.single, at);
    });
  });

  group('backwards compatible data', () {
    final pledge = {
      'id': 'p-1',
      'type': 'pledge',
      'timestamp': DateTime(2026, 1, 1, 9).toIso8601String(),
      'metadata': <String, dynamic>{},
    };

    for (
      var format = 1;
      format <= BackupService.currentBackupVersion;
      format++
    ) {
      test(
        'old backup format $format still imports, no rough day invented',
        () async {
          final preview = BackupService().validateBackupJson(
            jsonEncode({
              'version': format,
              'events': [pledge],
              'preferences': <String, dynamic>{},
            }),
          );
          expect(preview.eventCount, 1);
          await c.mergeImportedEvents(preview.events);
          expect(c.events.any((e) => e.id == 'p-1'), isTrue);
          expect(c.isRoughDay, isFalse);
          expect(c.roughDayUntil, isNull);
        },
      );
    }

    test(
      'backup stays at v12; a rough-day in local state is optional',
      () async {
        expect(BackupService.currentBackupVersion, 13);
        expect(RecoveryController.stateVersion, 18);
        await c.enterRoughDay(source: RoughDaySource.slip);
        final service = BackupService();
        final payload = service.buildBackupPayload(
          c.events,
          preferences: c.portablePreferences,
        );
        expect(payload['version'], 13);
        expect(jsonEncode(payload), isNot(contains('roughDayUntil')));
        final preview = service.validateBackupJson(jsonEncode(payload));
        await setUpController();
        await c.mergeImportedEvents(
          preview.events,
          preferences: Map<String, dynamic>.from(payload['preferences'] as Map),
          restorePreferences: true,
        );
        expect(c.isRoughDay, isFalse);
      },
    );

    test('state saved before this feature loads with no rough day', () async {
      await setUpController(
        stored: jsonEncode({
          'stateVersion': RecoveryController.stateVersion,
          'lastDose': DateTime(2026, 1, 1).toIso8601String(),
          'events': [pledge],
        }),
      );
      expect(c.loadStatus, RecoveryLoadStatus.ready);
      expect(c.isRoughDay, isFalse);
      expect(c.events, isNotEmpty);
    });
  });
}
