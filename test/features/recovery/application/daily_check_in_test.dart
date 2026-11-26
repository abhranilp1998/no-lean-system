import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/daily_check_in.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../../support/check_in_fakes.dart';
import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseline = DateTime(2026, 10, 1, 9);
  final tapAt = DateTime(2026, 11, 25, 20, 41);
  final now = DateTime(2026, 11, 26, 9);

  String state({Map<String, Object?> extra = const {}, int version = 17}) =>
      jsonEncode({
        'stateVersion': version,
        'events': [
          RecoveryEvent.create(
            type: RecoveryEventType.recoveryStart,
            timestamp: baseline,
          ).toJson(),
        ],
        'zones': [],
        ...extra,
      });

  Future<(RecoveryController, MemoryRecoveryStore, MemoryCheckInInbox)> loaded({
    String? stored,
    FakeRelapseLock? lock,
  }) async {
    final store = MemoryRecoveryStore(stored ?? state());
    final inbox = MemoryCheckInInbox();
    final controller = RecoveryController(
      store: store,
      relapseLock: lock ?? FakeRelapseLock(),
      checkInInbox: inbox,
      now: () => now,
    );
    await controller.load();
    return (controller, store, inbox);
  }

  test('no version bump: v17 without the keys loads off at 20:00', () async {
    expect(RecoveryController.stateVersion, 17);
    expect(BackupService.currentBackupVersion, 12);
    final (c, store, _) = await loaded();
    expect(c.dailyCheckIn, isFalse);
    expect(c.dailyCheckInMinutes, defaultCheckInMinutes);
    final saved = jsonDecode(store.value!) as Map;
    expect(saved['stateVersion'], 17);
  });

  test('toggle and time persist and survive a reload', () async {
    final (c, store, _) = await loaded();
    await c.setSetting('dailyCheckIn', true);
    await c.setSetting('dailyCheckInMinutes', 21 * 60 + 15);
    final saved = jsonDecode(store.value!) as Map;
    expect(saved['dailyCheckIn'], isTrue);
    expect(saved['dailyCheckInMinutes'], 21 * 60 + 15);
    expect(saved['stateVersion'], 17);
    final again = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await again.load();
    expect(again.dailyCheckIn, isTrue);
    expect(again.dailyCheckInMinutes, 21 * 60 + 15);
    // A bad time never sticks.
    await again.setSetting('dailyCheckInMinutes', 99999);
    expect(again.dailyCheckInMinutes, 21 * 60 + 15);
  });

  test('a malformed stored time falls back to 20:00', () async {
    final (c, _, _) = await loaded(
      stored: state(
        extra: {'dailyCheckIn': true, 'dailyCheckInMinutes': 'evening'},
      ),
    );
    expect(c.dailyCheckIn, isTrue);
    expect(c.dailyCheckInMinutes, defaultCheckInMinutes);
  });

  test(
    'Okay in the background becomes a clean check-in at the tap time',
    () async {
      final (c, _, inbox) = await loaded();
      await inbox.append(
        CheckInEntry(id: 'ok-1', answer: CheckInAnswer.okay, at: tapAt),
      );
      final first = await c.importCheckInInbox();
      expect(first.okay, 1);
      final event = c.events.singleWhere(
        (e) => e.type == RecoveryEventType.cleanCheckIn,
      );
      expect(event.timestamp, tapAt);
      expect(event.metadata['source'], 'checkin_notification');
      expect(c.cleanDays['2026-11-25'], isTrue);
      // Replaying the same entry adds nothing.
      await inbox.append(
        CheckInEntry(id: 'ok-1', answer: CheckInAnswer.okay, at: tapAt),
      );
      final replay = await c.importCheckInInbox();
      expect(replay.okay, 0);
      expect(
        c.events.where((e) => e.type == RecoveryEventType.cleanCheckIn),
        hasLength(1),
      );
    },
  );

  test(
    'Used in the background is a placeholder slip at tap time that counts as lean',
    () async {
      final (c, _, inbox) = await loaded();
      expect(c.lastDose, baseline);
      await inbox.append(
        CheckInEntry(id: 'used-1', answer: CheckInAnswer.used, at: tapAt),
      );
      final result = await c.importCheckInInbox();
      expect(result.used, 1);
      final slip = c.events.singleWhere(
        (e) => e.type == RecoveryEventType.relapse,
      );
      expect(slip.timestamp, tapAt, reason: 'occurredAt is the tap time');
      expect(slip.metadata[needsDetailsKey], isTrue);
      expect(slip.metadata['source'], 'checkin_notification');
      expect(slip.metadata.containsKey('relapseType'), isFalse);
      expect(c.lastDose, tapAt, reason: 'counts as lean until completed');
      expect(c.slipsNeedingDetails.single.id, slip.id);
      // Replay: no second slip.
      await inbox.append(
        CheckInEntry(id: 'used-1', answer: CheckInAnswer.used, at: tapAt),
      );
      await c.importCheckInInbox();
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        hasLength(1),
      );
    },
  );

  test(
    'completing as benzo-only recalculates and the lean timer goes back',
    () async {
      final (c, store, inbox) = await loaded();
      await inbox.append(
        CheckInEntry(id: 'used-2', answer: CheckInAnswer.used, at: tapAt),
      );
      await c.importCheckInInbox();
      final id = c.slipsNeedingDetails.single.id;
      expect(c.lastDose, tapAt);

      final result = await c.completeSlipDetails(
        id: id,
        type: RelapseType.benzo,
        note: 'one tablet',
      );
      expect(result, ProtectedActionResult.completed);
      final slip = c.events.firstWhere((e) => e.id == id);
      expect(slip.metadata['relapseType'], 'benzo');
      expect(slip.metadata['note'], 'one tablet');
      expect(slip.metadata.containsKey(needsDetailsKey), isFalse);
      expect(slip.metadata['streakLost'], 0);
      expect(
        c.lastDose,
        baseline,
        reason: 'benzo-only must not reset the timer',
      );
      expect(c.slipsNeedingDetails, isEmpty);
      // It is still in the log for safety checks and saved.
      expect(
        (jsonDecode(store.value!) as Map)['events'].toString(),
        contains('benzo'),
      );
    },
  );

  test('completing as lean, or keeping it, keeps the reset', () async {
    for (final type in [RelapseType.fullLean, null]) {
      final (c, _, inbox) = await loaded();
      await inbox.append(
        CheckInEntry(id: 'used-3', answer: CheckInAnswer.used, at: tapAt),
      );
      await c.importCheckInInbox();
      final id = c.slipsNeedingDetails.single.id;
      await c.completeSlipDetails(id: id, type: type);
      expect(c.lastDose, tapAt);
      expect(c.slipsNeedingDetails, isEmpty);
      final slip = c.events.firstWhere((e) => e.id == id);
      expect(slip.metadata['relapseType'], type?.name);
    }
  });

  test(
    'benzo-only completion asks the relapse lock; lean completion does not',
    () async {
      final lock = FakeRelapseLock()..pin = '4321';
      final (c, _, _) = await loaded(
        stored: state(extra: {'requirePinAfterRelapse': true}),
        lock: lock,
      );
      final recorded = await c.recordCheckInUsed(
        at: tapAt,
        pin: '4321',
        tryBiometrics: false,
      );
      expect(recorded, ProtectedActionResult.completed);
      final id = c.slipsNeedingDetails.single.id;
      expect(
        await c.completeSlipDetails(
          id: id,
          type: RelapseType.benzo,
          tryBiometrics: false,
        ),
        ProtectedActionResult.authenticationRequired,
      );
      expect(c.lastDose, tapAt);
      expect(
        await c.completeSlipDetails(
          id: id,
          type: RelapseType.benzo,
          pin: '4321',
          tryBiometrics: false,
        ),
        ProtectedActionResult.completed,
      );
      expect(c.lastDose, baseline);
    },
  );

  test(
    'with the relapse lock on, a background Used is handed to the app, never written',
    () async {
      final (c, _, inbox) = await loaded(
        stored: state(extra: {'requirePinAfterRelapse': true}),
      );
      await inbox.append(
        CheckInEntry(id: 'used-4', answer: CheckInAnswer.used, at: tapAt),
      );
      await inbox.append(
        CheckInEntry(id: 'ok-4', answer: CheckInAnswer.okay, at: tapAt),
      );
      final result = await c.importCheckInInbox();
      expect(result.askToLog, [tapAt]);
      expect(result.used, 0);
      expect(result.okay, 1);
      expect(
        c.events.where((e) => e.type == RecoveryEventType.relapse),
        isEmpty,
      );
      expect(c.lastDose, baseline);
      // Acknowledged: the same prompt is not repeated on the next resume.
      expect((await c.importCheckInInbox()).isEmpty, isTrue);
    },
  );

  test('two Used taps a few seconds apart are one slip', () async {
    final (c, _, _) = await loaded();
    await c.recordCheckInUsed(at: tapAt, entryId: 'one');
    await c.recordCheckInUsed(
      at: tapAt.add(const Duration(seconds: 20)),
      entryId: 'two',
    );
    expect(
      c.events.where((e) => e.type == RecoveryEventType.relapse),
      hasLength(1),
    );
  });

  test('a wrong tap can be removed and the timer returns', () async {
    final (c, _, _) = await loaded();
    await c.recordCheckInUsed(at: tapAt);
    expect(c.lastDose, tapAt);
    final id = c.slipsNeedingDetails.single.id;
    expect(await c.deleteEvent(id: id), ProtectedActionResult.completed);
    expect(c.lastDose, baseline);
  });

  test(
    'the placeholder flag and the settings survive a backup round-trip',
    () async {
      final (c, _, _) = await loaded();
      await c.setSetting('dailyCheckIn', true);
      await c.setSetting('dailyCheckInMinutes', 19 * 60 + 30);
      await c.recordCheckInUsed(at: tapAt);
      final service = BackupService();
      final json = jsonEncode(
        service.buildBackupPayload(
          c.events,
          preferences: c.portablePreferences,
        ),
      );
      final back = service.validateBackupJson(json);
      expect(back.preferences!['dailyCheckIn'], isTrue);
      expect(back.preferences!['dailyCheckInMinutes'], 19 * 60 + 30);
      expect(
        back.events.where((e) => e.metadata[needsDetailsKey] == true),
        hasLength(1),
      );
    },
  );

  test(
    'old backups (any format) import without the keys, and bad keys are refused',
    () {
      final service = BackupService();
      final events = [
        RecoveryEvent.create(
          type: RecoveryEventType.pledge,
          timestamp: DateTime(2026, 1, 1),
        ).toJson(),
      ];
      for (final version in [1, 6, 12]) {
        final preview = service.validateBackupJson(
          jsonEncode({
            'version': version,
            'events': events,
            'preferences': {'riskReminders': true},
          }),
        );
        expect(preview.preferences, isNot(contains('dailyCheckIn')));
        expect(preview.eventCount, 1);
      }
      for (final bad in [
        {'dailyCheckIn': 'yes'},
        {'dailyCheckInMinutes': 2000},
        {'dailyCheckInMinutes': '8pm'},
      ]) {
        expect(
          () => service.validateBackupJson(
            jsonEncode({'version': 12, 'events': events, 'preferences': bad}),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
