import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/cravings/domain/urge_ride.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late RecoveryController c;
  late MemoryRecoveryStore store;
  late int cravingNotifs;
  late int useChecks;

  Future<void> setUpController({String? stored}) async {
    now = DateTime.now();
    cravingNotifs = 0;
    useChecks = 0;
    store = MemoryRecoveryStore(stored);
    c = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
      scheduleCravingCheck: (_) async {
        cravingNotifs++;
        return true;
      },
      cancelCravingCheck: () async {},
      scheduleUseCheck: (_) async {
        useChecks++;
        return true;
      },
      cancelUseCheck: () async {},
    );
    await c.load();
  }

  setUp(() => setUpController());

  test('saving a ride keeps the events and does not nag later', () async {
    await c.recordUrgeRide(
      startedAt: now.subtract(const Duration(minutes: 10)),
      outcome: UrgeRideOutcome.yes,
      activity: UrgeRideActivity.walk,
      hapticPacing: true,
      intensityBefore: 7,
    );
    expect(c.urgeRides, hasLength(1));
    expect(c.urgeRides.single.activity, UrgeRideActivity.walk);
    expect(c.urgeRides.single.outcome, UrgeRideOutcome.yes);
    expect(c.whatWorked.passed, 1);
    expect(cravingNotifs, 0);
    expect(useChecks, 0);
    final check = c.events.lastWhere(
      (e) => e.type == RecoveryEventType.cravingCheck,
    );
    expect(check.metadata['urgeRide'], isTrue);
    expect(check.metadata['activity'], 'walk');
    expect(check.metadata['outcome'], 'gone');
  });

  test('stats survive a restart from saved state', () async {
    await c.recordUrgeRide(
      startedAt: now.subtract(const Duration(minutes: 10)),
      outcome: UrgeRideOutcome.aBit,
      activity: UrgeRideActivity.music,
    );
    final restarted = RecoveryController(
      store: MemoryRecoveryStore(store.value),
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await restarted.load();
    expect(restarted.urgeRides.single.outcome, UrgeRideOutcome.aBit);
    expect(restarted.whatWorked.eased, 1);
  });

  test(
    'a benzo-only slip never has to do with this, and lastDose is untouched',
    () async {
      final before = c.lastDose;
      await c.recordUrgeRide(
        startedAt: now.subtract(const Duration(minutes: 8)),
        outcome: UrgeRideOutcome.no,
        activity: UrgeRideActivity.breathing,
      );
      expect(c.lastDose, before);
    },
  );

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
        'old backup format $format still imports, no rides invented',
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
          expect(c.urgeRides, isEmpty);
          expect(c.whatWorked.total, 0);
        },
      );
    }

    test(
      'backup stays at v12; a ride round-trips as optional metadata',
      () async {
        expect(BackupService.currentBackupVersion, 13);
        expect(RecoveryController.stateVersion, 18);
        await c.recordUrgeRide(
          startedAt: now.subtract(const Duration(minutes: 10)),
          outcome: UrgeRideOutcome.yes,
          activity: UrgeRideActivity.shower,
        );
        final service = BackupService();
        final payload = service.buildBackupPayload(
          c.events,
          preferences: c.portablePreferences,
        );
        expect(payload['version'], 13);
        final preview = service.validateBackupJson(jsonEncode(payload));
        await setUpController();
        await c.mergeImportedEvents(preview.events);
        expect(c.urgeRides, hasLength(1));
        expect(c.urgeRides.single.activity, UrgeRideActivity.shower);
        expect(c.whatWorked.passed, 1);
      },
    );

    test('state saved before this feature loads with no rides', () async {
      await setUpController(
        stored: jsonEncode({
          'stateVersion': RecoveryController.stateVersion,
          'lastDose': DateTime(2026, 1, 1).toIso8601String(),
          'events': [pledge],
        }),
      );
      expect(c.loadStatus, RecoveryLoadStatus.ready);
      expect(c.urgeRides, isEmpty);
      expect(c.events, isNotEmpty);
    });
  });
}
