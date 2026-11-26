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
}
