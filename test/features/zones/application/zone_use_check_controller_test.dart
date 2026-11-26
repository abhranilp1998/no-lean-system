import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/event_derived_state.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/domain/use_check.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/zones/domain/zone_entry.dart';
import 'package:no_lean/features/zones/domain/zone_use_check.dart';
import 'package:no_lean/features/zones/services/zone_entry_inbox.dart';

import '../../../support/recovery_fakes.dart';

class _Inbox implements ZoneEntryInbox {
  final pending = <ZoneEntry>[];
  @override
  Future<void> append(ZoneEntry entry) async => pending.add(entry);
  @override
  Future<List<ZoneEntry>> drain() async => List.of(pending);
  @override
  Future<void> acknowledge() async => pending.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The clock is the real "now": the controller's own clock and the
  // relapse logger both use it for "not in the future".
  var now = DateTime.now();
  DateTime ago(Duration d) => now.subtract(d);

  late RecoveryController c;
  late _Inbox inbox;
  late List<UseCheck> queued;
  late UseCheck? stored; // what the notification service would hold
  late String? ledger;
  late int cancels;

  Future<void> setUpController({bool history = true}) async {
    now = DateTime.now();
    queued = [];
    stored = null;
    ledger = null;
    cancels = 0;
    inbox = _Inbox();
    c = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      zoneInbox: inbox,
      now: () => now,
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
      scheduleUseCheck: (check) async {
        queued.add(check);
        stored = check;
        return true;
      },
      cancelUseCheck: () async {
        cancels++;
        stored = null;
      },
      peekUseCheck: () async => stored,
      takeUseCheck: () async {
        final s = stored;
        stored = null;
        return s;
      },
      readZoneLedger: () async => ledger,
      writeZoneLedger: (v) async => ledger = v,
    );
    await c.load();
    if (history) await c.setZoneHistory(true);
  }

  ZoneEntry visit(
    Duration agoBy, {
    String zone = 'z1',
    String name = 'Old bar',
  }) => ZoneEntry(zoneId: zone, zoneName: name, at: ago(agoBy), source: 'app');

  setUp(() => setUpController());

  group('queueing', () {
    test('a zone visit queues one check an hour after arriving', () async {
      final entry = visit(const Duration(minutes: 1));
      expect(await c.maybeQueueZoneUseCheck(entry), isTrue);
      final check = queued.single;
      expect(check.trigger, UseCheckTrigger.zoneVisit);
      expect(check.triggeredAt, entry.at);
      expect(check.dueAt, entry.at.add(const Duration(hours: 1)));
      expect(check.zoneName, 'Old bar');
      expect(c.pendingUseCheck, same(check));
    });

    test('recording an in-app entry asks about it', () async {
      await c.recordZoneEntry(visit(const Duration(minutes: 1)));
      await pumpEventQueue();
      expect(queued.single.trigger, UseCheckTrigger.zoneVisit);
    });

    test(
      'works with zone history off, and then never keeps the name',
      () async {
        await setUpController(history: false);
        await c.recordZoneEntry(visit(const Duration(minutes: 1)));
        await pumpEventQueue();
        expect(
          c.events.where((e) => e.type == RecoveryEventType.zoneEntry),
          isEmpty,
        );
        expect(queued.single.zoneName, isNull);
        expect(queued.single.zoneId, isNull);
        expect(jsonEncode(ledger), isNot(contains('Old bar')));
      },
    );

    test('once per visit: the same visit twice is one question', () async {
      expect(
        await c.maybeQueueZoneUseCheck(visit(const Duration(minutes: 3))),
        isTrue,
      );
      expect(
        await c.maybeQueueZoneUseCheck(visit(const Duration(minutes: 1))),
        isFalse,
      );
      expect(queued, hasLength(1));
    });

    test('rate limits hold across restarts (ledger is persisted)', () async {
      await c.maybeQueueZoneUseCheck(visit(const Duration(minutes: 3)));
      final saved = ledger;
      await setUpController();
      ledger = saved;
      expect(
        await c.maybeQueueZoneUseCheck(visit(const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('a visit older than a day is not asked about', () async {
      expect(
        await c.maybeQueueZoneUseCheck(visit(const Duration(hours: 30))),
        isFalse,
      );
    });

    test('a broken ledger store never blocks or crashes', () async {
      ledger = 'garbage';
      expect(
        await c.maybeQueueZoneUseCheck(visit(const Duration(minutes: 1))),
        isTrue,
      );
    });

    test('background visits: only the newest is asked about', () async {
      inbox.pending
        ..add(visit(const Duration(hours: 5), zone: 'a', name: 'A'))
        ..add(visit(const Duration(hours: 2), zone: 'b', name: 'B'));
      await c.importZoneInbox();
      await pumpEventQueue();
      expect(queued.single.zoneName, 'B');
    });

    test(
      'the exit button does not replace a waiting zone-visit check',
      () async {
        await c.maybeQueueZoneUseCheck(visit(const Duration(minutes: 1)));
        await c.queueUseCheck(UseCheckTrigger.zoneExit);
        expect(c.pendingUseCheck?.trigger, UseCheckTrigger.zoneVisit);
        expect(queued, hasLength(1));
      },
    );
  });

  group('the card', () {
    test('appears only once due, and vanishes after expiry', () async {
      await c.maybeQueueZoneUseCheck(visit(const Duration(minutes: 1)));
      expect(c.dueZoneUseCheck, isNull);
      now = now.add(const Duration(hours: 1, minutes: 1));
      expect(c.dueZoneUseCheck, isNotNull);
      now = now.add(const Duration(hours: 25));
      expect(c.dueZoneUseCheck, isNull);
    });

    test('other kinds of check never show the zone card', () async {
      await c.queueUseCheck(
        UseCheckTrigger.craving,
        at: ago(const Duration(hours: 2)),
      );
      expect(c.dueZoneUseCheck, isNull);
    });
  });

  group('answers', () {
    test(
      'NO counts a zone resisted, with the place, and clears the check',
      () async {
        await c.maybeQueueZoneUseCheck(visit(const Duration(hours: 2)));
        final check = (await c.takePendingUseCheck())!;
        final count = await c.answerUseCheckClean(check);
        expect(count, 1);
        expect(c.zonesResisted, 1);
        final e = c.events.lastWhere(
          (e) => e.type == RecoveryEventType.cleanCheckIn,
        );
        expect(e.metadata['zoneResisted'], isTrue);
        expect(e.metadata['zoneName'], 'Old bar');
        expect(e.metadata['visitAt'], check.triggeredAt.toIso8601String());
        expect(c.pendingUseCheck, isNull);
        // A second zone resisted later keeps counting.
        await c.answerUseCheckClean(check);
        expect(c.zonesResisted, 2);
      },
    );

    test('NO without zone history keeps the place out of the record', () async {
      await setUpController(history: false);
      await c.maybeQueueZoneUseCheck(visit(const Duration(hours: 2)));
      await c.answerUseCheckClean(await c.takePendingUseCheck());
      final e = c.events.lastWhere(
        (e) => e.type == RecoveryEventType.cleanCheckIn,
      );
      expect(e.metadata['zoneResisted'], isTrue);
      expect(e.metadata.containsKey('zoneName'), isFalse);
    });

    test('NO on a non-zone check is a plain safe check-in', () async {
      await c.answerUseCheckClean(
        UseCheck(
          trigger: UseCheckTrigger.craving,
          triggeredAt: ago(const Duration(hours: 1)),
        ),
      );
      expect(c.zonesResisted, 0);
      expect(
        c.events
            .lastWhere((e) => e.type == RecoveryEventType.cleanCheckIn)
            .metadata,
        isEmpty,
      );
    });

    test('NO never touches the lean clean timer', () async {
      final before = c.lastDose;
      await c.answerUseCheckClean(
        UseCheck(
          trigger: UseCheckTrigger.zoneVisit,
          triggeredAt: ago(const Duration(hours: 2)),
          zoneName: 'x',
        ),
      );
      expect(c.lastDose, before);
    });

    test('LATER snoozes 30 min twice, then the question is dropped', () async {
      await c.maybeQueueZoneUseCheck(visit(const Duration(hours: 2)));
      var check = c.pendingUseCheck!;
      expect(await c.snoozeUseCheck(check), isTrue);
      check = c.pendingUseCheck!;
      expect(check.snoozes, 1);
      expect(check.dueAt, now.add(useCheckSnooze));
      expect(c.dueZoneUseCheck, isNull); // hidden while snoozed
      now = now.add(const Duration(minutes: 31));
      expect(c.dueZoneUseCheck, isNotNull);
      expect(await c.snoozeUseCheck(c.pendingUseCheck!), isTrue);
      now = now.add(const Duration(minutes: 31));
      expect(await c.snoozeUseCheck(c.pendingUseCheck!), isFalse);
      expect(c.pendingUseCheck, isNull);
      expect(cancels, greaterThan(0));
    });

    test(
      'YES: the logger time is the visit time, and saving clears the check',
      () async {
        final entry = visit(const Duration(hours: 3));
        await c.maybeQueueZoneUseCheck(entry);
        final check = c.pendingUseCheck!;
        expect(useCheckPrefill(check, now), entry.at);
        await c.recordRelapse(
          entries: [
            RelapseLogEntry(
              occurredAt: useCheckPrefill(check, now),
              type: RelapseType.fullLean,
              note: zoneCheckPrefillNote(check),
              attemptedSos: false,
            ),
          ],
        );
        final relapse = c.events.lastWhere(
          (e) => e.type == RecoveryEventType.relapse,
        );
        expect(relapse.timestamp, entry.at); // occurredAt = visit time
        expect(
          relapse.metadata['recordedAt'],
          isNot(entry.at.toIso8601String()),
        );
        expect(relapse.metadata['note'], 'After a visit to Old bar.');
        expect(c.lastDose, entry.at);
        expect(c.pendingUseCheck, isNull);
        expect(stored, isNull);
      },
    );

    test(
      'YES with benzo only keeps the lean timer (logged for safety)',
      () async {
        final entry = visit(const Duration(hours: 3));
        await c.maybeQueueZoneUseCheck(entry);
        final before = c.lastDose;
        await c.recordRelapse(
          entries: [
            RelapseLogEntry(
              occurredAt: entry.at,
              type: RelapseType.benzo,
              note: zoneCheckPrefillNote(c.pendingUseCheck!),
              attemptedSos: false,
            ),
          ],
        );
        expect(
          c.events.where((e) => e.type == RecoveryEventType.relapse),
          hasLength(1),
        );
        expect(c.lastDose, before);
        expect(
          resetsLeanCleanTimer(
            c.events.lastWhere((e) => e.type == RecoveryEventType.relapse),
          ),
          isFalse,
        );
      },
    );
  });

  group('backwards compatible data', () {
    final pledge = {
      'id': 'p-1',
      'type': 'pledge',
      'timestamp': DateTime(2026, 1, 1, 9).toIso8601String(),
      'metadata': <String, dynamic>{},
    };
    final oldCheckIn = {
      'id': 'c-old',
      'type': 'cleanCheckIn',
      'timestamp': DateTime(2026, 1, 2, 9).toIso8601String(),
      'metadata': <String, dynamic>{},
    };
    final resisted = {
      'id': 'c-zone',
      'type': 'cleanCheckIn',
      'timestamp': DateTime(2026, 1, 3, 9).toIso8601String(),
      'metadata': {
        'source': 'use_check',
        'zoneResisted': true,
        'zoneName': 'Old bar',
      },
    };

    for (
      var format = 1;
      format <= BackupService.currentBackupVersion;
      format++
    ) {
      test(
        'old backup format $format still imports, old check-ins intact',
        () async {
          final preview = BackupService().validateBackupJson(
            jsonEncode({
              'version': format,
              'events': [pledge, oldCheckIn],
              'preferences': <String, dynamic>{},
            }),
          );
          expect(preview.eventCount, 2);
          await c.mergeImportedEvents(preview.events);
          final imported = c.events.firstWhere((e) => e.id == 'c-old');
          expect(imported.type, RecoveryEventType.cleanCheckIn);
          expect(imported.metadata, isEmpty);
          expect(c.zonesResisted, 0); // nothing invented from old data
        },
      );
    }

    test('backup stays at v12; zone-resisted check-ins round-trip', () async {
      expect(BackupService.currentBackupVersion, 13);
      final service = BackupService();
      final payload = service.buildBackupPayload([
        RecoveryEvent.fromJson(pledge),
        RecoveryEvent.fromJson(resisted),
      ], preferences: c.portablePreferences);
      expect(payload['version'], 13);
      final preview = service.validateBackupJson(jsonEncode(payload));
      await c.mergeImportedEvents(preview.events);
      expect(c.zonesResisted, 1);
      expect(
        c.events.firstWhere((e) => e.id == 'c-zone').metadata['zoneName'],
        'Old bar',
      );
    });

    test(
      'state saved before this feature loads with no pending check',
      () async {
        final store = MemoryRecoveryStore(
          jsonEncode({
            'stateVersion': RecoveryController.stateVersion,
            'lastDose': DateTime(2026, 1, 1).toIso8601String(),
            'events': [pledge, oldCheckIn],
          }),
        );
        final old = RecoveryController(
          store: store,
          relapseLock: FakeRelapseLock(),
          peekUseCheck: () async => null,
        );
        await old.load();
        expect(old.loadStatus, RecoveryLoadStatus.ready);
        expect(
          old.events.where((e) => e.type == RecoveryEventType.cleanCheckIn),
          hasLength(1),
        );
        expect(old.dueZoneUseCheck, isNull);
        expect(old.zonesResisted, 0);
      },
    );
  });
}
