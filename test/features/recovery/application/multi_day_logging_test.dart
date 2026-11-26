import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/dose_units.dart';
import 'package:no_lean/features/recovery/domain/event_derived_state.dart';
import 'package:no_lean/features/recovery/domain/multi_day_log.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = DateTime.now();
  DateTime daysAgo(int n, [int hour = 21]) =>
      DateTime(today.year, today.month, today.day - n, hour);

  Future<RecoveryController> controller({List<RecoveryEvent>? seed}) async {
    final store = MemoryRecoveryStore();
    final c = RecoveryController(store: store, relapseLock: FakeRelapseLock());
    await c.load();
    // Start the clean timer well before the days being caught up.
    await c.recordRelapse(
      entries: [
        RelapseLogEntry(
          occurredAt: daysAgo(30, 10),
          type: RelapseType.fullLean,
          note: 'Starting point for this test.',
          attemptedSos: false,
        ),
      ],
    );
    return c;
  }

  RelapseLogEntry template(RelapseType type) => RelapseLogEntry(
    occurredAt: today,
    type: type,
    note: 'Logging this later for days I missed.',
    attemptedSos: false,
    contextTags: const ['Stress'],
    dose: DoseAmount.entered(1, DoseUnit.bottle, bottleMl: 100),
    cost: 150,
  );

  Future<List<RecoveryEvent>> saveDays(
    RecoveryController c,
    RelapseType type,
    List<int> agos,
  ) async {
    final slots = buildMultiDaySlots([
      for (final n in agos) daysAgo(n),
    ], now: DateTime.now());
    final result = await c.recordRelapse(
      entries: expandMultiDayEntries(template(type), slots),
      extraMetadata: const {multiDayMetadataKey: true},
    );
    expect(result, ProtectedActionResult.completed);
    return c.events
        .where((e) => e.metadata[multiDayMetadataKey] == true)
        .toList();
  }

  test('bulk create writes one independent event per picked day', () async {
    final c = await controller();
    final saved = await saveDays(c, RelapseType.fullLean, [5, 3, 2]);
    expect(saved, hasLength(3));
    expect(saved.map((e) => e.id).toSet(), hasLength(3));
    expect(saved.map((e) => e.timestamp), [daysAgo(5), daysAgo(3), daysAgo(2)]);
    // Same save moment, different occurred times.
    expect(saved.map((e) => e.metadata['recordedAt']).toSet(), hasLength(1));
    expect(saved.map((e) => e.metadata['batchId']).toSet(), hasLength(1));
    for (final e in saved) {
      expect(e.metadata['note'], 'Logging this later for days I missed.');
      expect(e.metadata['amountMl'], 100);
      expect(e.metadata['cost'], 150);
    }
    // Clean time counts from the latest picked day (occurredAt).
    expect(c.lastDose, daysAgo(2));
    expect(c.streak, DateTime.now().difference(daysAgo(2)).inDays);
  });

  test('editing one day changes only that entry and its time', () async {
    final c = await controller();
    final saved = await saveDays(c, RelapseType.fullLean, [5, 3, 2]);
    final middle = saved[1];
    final result = await c.editRelapseEntry(
      id: middle.id,
      entry: RelapseLogEntry(
        occurredAt: daysAgo(3, 14),
        type: RelapseType.partial,
        note: 'Actually only a sip in the afternoon.',
        attemptedSos: true,
      ),
    );
    expect(result, ProtectedActionResult.completed);
    final after = {for (final e in c.events) e.id: e};
    final edited = after[middle.id]!;
    expect(edited.timestamp, daysAgo(3, 14));
    expect(edited.metadata['relapseType'], 'partial');
    expect(edited.metadata['attemptedSos'], isTrue);
    expect(edited.metadata.containsKey('amount'), isFalse);
    expect(edited.metadata.containsKey('cost'), isFalse);
    expect(edited.metadata['editedAt'], isA<String>());
    expect(edited.metadata['recordedAt'], middle.metadata['recordedAt']);
    expect(edited.metadata['batchId'], middle.metadata['batchId']);
    expect(edited.metadata[multiDayMetadataKey], isTrue);
    for (final other in [saved[0], saved[2]]) {
      expect(after[other.id]!.timestamp, other.timestamp);
      expect(after[other.id]!.metadata, other.metadata);
    }
  });

  test('editing a day into the future is refused', () async {
    final c = await controller();
    final saved = await saveDays(c, RelapseType.fullLean, [2]);
    expect(
      () => c.editRelapseEntry(
        id: saved.single.id,
        entry: RelapseLogEntry(
          occurredAt: DateTime.now().add(const Duration(days: 1)),
          type: RelapseType.fullLean,
          note: 'This should never be saved.',
          attemptedSos: false,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('moving the latest day earlier moves clean time back too', () async {
    final c = await controller();
    final saved = await saveDays(c, RelapseType.fullLean, [6, 2]);
    expect(c.lastDose, daysAgo(2));
    await c.editRelapseEntry(
      id: saved.last.id,
      entry: template(RelapseType.fullLean).copyWith(occurredAt: daysAgo(8)),
    );
    expect(c.lastDose, daysAgo(6));
  });

  test('deleting one day leaves the other days in place', () async {
    final c = await controller();
    final saved = await saveDays(c, RelapseType.fullLean, [5, 3, 2]);
    final result = await c.deleteEvent(id: saved.last.id);
    expect(result, ProtectedActionResult.completed);
    final left = c.events
        .where((e) => e.metadata[multiDayMetadataKey] == true)
        .map((e) => e.id);
    expect(left, [saved[0].id, saved[1].id]);
    expect(c.lastDose, daysAgo(3));
  });

  test('benzo-only bulk is kept for safety but keeps the lean timer', () async {
    final c = await controller();
    final before = c.lastDose;
    final saved = await saveDays(c, RelapseType.benzo, [4, 2, 1]);
    expect(saved, hasLength(3));
    expect(saved.every((e) => e.metadata['relapseType'] == 'benzo'), isTrue);
    expect(saved.every((e) => e.metadata['streakLost'] == 0), isTrue);
    expect(c.lastDose, before);
    expect(c.streak, DateTime.now().difference(daysAgo(30, 10)).inDays);
    // The benzo days are not marked unclean on the lean heat map.
    final key = daysAgo(2).toIso8601String().substring(0, 10);
    expect(computeCleanDaysMap(c.events)[key], isNot(false));
  });

  test('a later lean day in the same catch-up still resets', () async {
    final c = await controller();
    final slots = buildMultiDaySlots([daysAgo(4)], now: DateTime.now());
    await c.recordRelapse(
      entries: [
        ...expandMultiDayEntries(template(RelapseType.benzo), slots),
        template(RelapseType.fullLean).copyWith(occurredAt: daysAgo(3)),
      ],
      extraMetadata: const {multiDayMetadataKey: true},
    );
    expect(c.lastDose, daysAgo(3));
  });

  test(
    'switching a benzo day to lean in an edit resets from that day',
    () async {
      final c = await controller();
      final saved = await saveDays(c, RelapseType.benzo, [3]);
      expect(c.streak, DateTime.now().difference(daysAgo(30, 10)).inDays);
      await c.editRelapseEntry(
        id: saved.single.id,
        entry: template(RelapseType.fullLean).copyWith(occurredAt: daysAgo(3)),
      );
      expect(c.lastDose, daysAgo(3));
      expect(
        c.events
            .firstWhere((e) => e.id == saved.single.id)
            .metadata['streakLost'],
        daysAgo(3).difference(daysAgo(30, 10)).inDays,
      );
    },
  );

  test('multi-day entries survive backup export and import (v12)', () async {
    final c = await controller();
    final saved = await saveDays(c, RelapseType.fullLean, [5, 3, 2]);
    await c.editRelapseEntry(
      id: saved[0].id,
      entry: template(RelapseType.benzo).copyWith(occurredAt: daysAgo(5, 8)),
    );
    final service = BackupService();
    final payload = service.buildBackupPayload(
      c.events,
      preferences: c.portablePreferences,
    );
    expect(payload['version'], 12);
    final preview = service.validateBackupJson(jsonEncode(payload));
    final restored = {for (final e in preview.events) e.id: e};
    for (final e in c.events.where(
      (e) => e.metadata[multiDayMetadataKey] == true,
    )) {
      expect(restored[e.id], isNotNull);
      expect(restored[e.id]!.timestamp, e.timestamp);
      expect(restored[e.id]!.metadata, e.metadata);
    }
    expect(preview.hiddenDuplicates, isEmpty);

    // Importing into a fresh install gives the same clean time.
    final fresh = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
    );
    await fresh.load();
    await fresh.mergeImportedEvents(preview.events);
    expect(fresh.lastDose, c.lastDose);
    expect(
      fresh.events.where((e) => e.metadata[multiDayMetadataKey] == true),
      hasLength(3),
    );
  });

  group('several doses on the same day', () {
    List<MultiDaySlot> doses(int ago, List<int> hours) => [
      for (final h in hours)
        MultiDaySlot(day: dayOnly(daysAgo(ago)), hour: h, minute: 0),
    ];

    Future<List<RecoveryEvent>> saveSlots(
      RecoveryController c,
      RelapseType type,
      List<MultiDaySlot> slots,
    ) async {
      final result = await c.recordRelapse(
        entries: expandMultiDayEntries(template(type), sortedSlots(slots)),
        extraMetadata: const {multiDayMetadataKey: true},
      );
      expect(result, ProtectedActionResult.completed);
      return c.events
          .where((e) => e.metadata[multiDayMetadataKey] == true)
          .toList();
    }

    test('each dose becomes its own independent entry', () async {
      final c = await controller();
      final saved = await saveSlots(c, RelapseType.fullLean, [
        ...doses(4, [9, 15, 21]),
        ...doses(2, [13, 22]),
      ]);
      expect(saved, hasLength(5));
      expect(saved.map((e) => e.id).toSet(), hasLength(5));
      expect(saved.map((e) => e.timestamp.hour), [9, 15, 21, 13, 22]);
      expect(saved.map((e) => e.metadata['batchId']).toSet(), hasLength(1));
      expect(saved.map((e) => e.metadata['recordedAt']).toSet(), hasLength(1));
      // Clean time counts from the latest dose.
      expect(c.lastDose, daysAgo(2, 22));
    });

    test('a per-dose override changes only that dose', () async {
      final c = await controller();
      final tablets = DoseAmount.entered(2, DoseUnit.tablet, bottleMl: 100);
      final slots = doses(3, [10, 20]);
      final saved = await saveSlots(c, RelapseType.fullLean, [
        slots[0],
        slots[1].withOverride(type: RelapseType.benzo, dose: tablets),
      ]);
      expect(saved[0].metadata['relapseType'], 'fullLean');
      expect(saved[0].metadata['amountMl'], 100);
      expect(saved[1].metadata['relapseType'], 'benzo');
      expect(saved[1].metadata['unit'], 'tablet');
      expect(saved[1].metadata.containsKey('amountMl'), isFalse);
    });

    test('editing and deleting one dose leaves the same-day doses', () async {
      final c = await controller();
      final saved = await saveSlots(
        c,
        RelapseType.fullLean,
        doses(3, [9, 15, 21]),
      );
      final other = [saved[0].metadata, saved[2].metadata];
      expect(
        await c.editRelapseEntry(
          id: saved[1].id,
          entry: template(
            RelapseType.fullLean,
          ).copyWith(occurredAt: daysAgo(3, 16)),
        ),
        ProtectedActionResult.completed,
      );
      expect(
        c.events.firstWhere((e) => e.id == saved[1].id).timestamp.hour,
        16,
      );
      expect(
        c.events.firstWhere((e) => e.id == saved[0].id).metadata,
        other[0],
      );
      expect(
        await c.deleteEvent(id: saved[2].id),
        ProtectedActionResult.completed,
      );
      final left = c.events
          .where((e) => e.metadata[multiDayMetadataKey] == true)
          .map((e) => e.id);
      expect(left, [saved[0].id, saved[1].id]);
      expect(c.lastDose, daysAgo(3, 16));
    });

    test(
      'benzo and lean on the same day: timer follows the lean dose',
      () async {
        final c = await controller();
        final slots = doses(2, [15, 23]);
        final saved = await saveSlots(c, RelapseType.fullLean, [
          slots[0],
          slots[1].withOverride(type: RelapseType.benzo),
        ]);
        // The later benzo dose is kept but does not move the lean timer.
        expect(c.lastDose, daysAgo(2, 15));
        expect(saved[1].metadata['relapseType'], 'benzo');
        expect(saved[1].metadata['streakLost'], 0);
        expect(saved[0].metadata['streakLost'], 28);
        // And the other way round: an earlier benzo dose, later lean dose.
        final d = await controller();
        final s2 = doses(2, [9, 20]);
        await saveSlots(d, RelapseType.fullLean, [
          s2[0].withOverride(type: RelapseType.benzo),
          s2[1],
        ]);
        expect(d.lastDose, daysAgo(2, 20));
      },
    );

    test('benzo-only doses all day never reset the lean timer', () async {
      final c = await controller();
      final before = c.lastDose;
      await saveSlots(c, RelapseType.benzo, doses(2, [9, 15, 21]));
      expect(c.lastDose, before);
    });

    test('the 50-entry cap counts every dose', () async {
      final c = await controller();
      Future<ProtectedActionResult> save(int days, int perDay) =>
          c.recordRelapse(
            entries: expandMultiDayEntries(template(RelapseType.fullLean), [
              for (var d = 1; d <= days; d++)
                ...doses(d, [for (var i = 0; i < perDay; i++) 8 + i]),
            ]),
            extraMetadata: const {multiDayMetadataKey: true},
          );
      await expectLater(save(6, 9), throwsArgumentError); // 54 entries
      expect(
        c.events.where((e) => e.metadata[multiDayMetadataKey] == true),
        isEmpty,
      );
      expect(await save(5, 10), ProtectedActionResult.completed); // 50
      expect(
        c.events.where((e) => e.metadata[multiDayMetadataKey] == true),
        hasLength(50),
      );
    });

    test('doses in the future are refused', () async {
      final c = await controller();
      await expectLater(
        c.recordRelapse(
          entries: [
            template(RelapseType.fullLean).copyWith(
              occurredAt: DateTime.now().add(const Duration(hours: 2)),
            ),
          ],
          extraMetadata: const {multiDayMetadataKey: true},
        ),
        throwsArgumentError,
      );
    });

    test('multiple doses per day survive backup export and import', () async {
      final c = await controller();
      final slots = doses(3, [9, 21]);
      await saveSlots(c, RelapseType.fullLean, [
        slots[0].withOverride(type: RelapseType.benzo),
        slots[1],
      ]);
      final service = BackupService();
      final payload = service.buildBackupPayload(
        c.events,
        preferences: c.portablePreferences,
      );
      expect(payload['version'], 12);
      final preview = service.validateBackupJson(jsonEncode(payload));
      final fresh = RecoveryController(
        store: MemoryRecoveryStore(),
        relapseLock: FakeRelapseLock(),
      );
      await fresh.load();
      await fresh.mergeImportedEvents(preview.events);
      expect(fresh.lastDose, c.lastDose);
      expect(
        fresh.events
            .where((e) => e.metadata[multiDayMetadataKey] == true)
            .map((e) => (e.timestamp, e.metadata['relapseType'])),
        c.events
            .where((e) => e.metadata[multiDayMetadataKey] == true)
            .map((e) => (e.timestamp, e.metadata['relapseType'])),
      );
    });
  });

  group('backwards compatibility', () {
    test('an old backup (no multi-day or dose fields) still imports', () async {
      final old = {
        'version': 5,
        'events': [
          {
            'id': 'old-relapse',
            'type': 'relapse',
            'timestamp': DateTime(2026, 3, 1, 22).toIso8601String(),
            'metadata': <String, dynamic>{'streakLost': 4},
          },
          {
            'id': 'old-relapse-2',
            'type': 'relapse',
            'timestamp': DateTime(2026, 4, 1, 22).toIso8601String(),
            'metadata': <String, dynamic>{'relapseType': 'benzo'},
          },
        ],
        'preferences': <String, dynamic>{},
      };
      final preview = BackupService().validateBackupJson(jsonEncode(old));
      expect(preview.eventCount, 2);
      final fresh = RecoveryController(
        store: MemoryRecoveryStore(),
        relapseLock: FakeRelapseLock(),
      );
      await fresh.load();
      await fresh.mergeImportedEvents(preview.events);
      expect(
        fresh.events.map((e) => e.id),
        containsAll(['old-relapse', 'old-relapse-2']),
      );
      final baseline = fresh.events.length;
      expect(
        fresh.events
            .firstWhere((e) => e.id == 'old-relapse')
            .metadata['streakLost'],
        4,
      );
      // Nothing was rewritten, and new multi-dose saves work on top.
      final result = await fresh.recordRelapse(
        entries: expandMultiDayEntries(template(RelapseType.fullLean), [
          MultiDaySlot(day: dayOnly(daysAgo(2)), hour: 9, minute: 0),
          MultiDaySlot(day: dayOnly(daysAgo(2)), hour: 21, minute: 0),
        ]),
        extraMetadata: const {multiDayMetadataKey: true},
      );
      expect(result, ProtectedActionResult.completed);
      expect(fresh.events, hasLength(baseline + 2));
    });

    test(
      'a PR #26 backup (one entry per day) still imports unchanged',
      () async {
        final c = await controller();
        await saveDays(c, RelapseType.fullLean, [5, 3]);
        final json = jsonEncode(
          BackupService().buildBackupPayload(
            c.events,
            preferences: c.portablePreferences,
          ),
        );
        final preview = BackupService().validateBackupJson(json);
        expect(preview.eventCount, c.events.length);
      },
    );
  });
}
