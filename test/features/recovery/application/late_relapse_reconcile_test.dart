import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/milestones.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

/// End-to-end: a relapse logged late moves clean time, best streak and
/// milestones to its *occurred* time, through record, edit, delete, import
/// and reload.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final start = DateTime(2026, 10, 1, 9);
  DateTime day(num d) => start.add(Duration(minutes: (d * 24 * 60).round()));

  Future<(RecoveryController, MemoryRecoveryStore, void Function(DateTime))>
  loaded({List<RecoveryEvent> extra = const []}) async {
    var now = day(4);
    final store = MemoryRecoveryStore(
      jsonEncode({
        'stateVersion': RecoveryController.stateVersion,
        'events': [
          RecoveryEvent.create(
            type: RecoveryEventType.recoveryStart,
            timestamp: start,
          ).toJson(),
          for (final e in extra) e.toJson(),
        ],
      }),
    );
    final c = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => now,
    );
    await c.load();
    return (c, store, (DateTime next) => now = next);
  }

  List<RecoveryEvent> milestones(RecoveryController c) =>
      c.events.where((e) => e.type == RecoveryEventType.milestone).toList();

  RelapseLogEntry entry(DateTime at, RelapseType type) => RelapseLogEntry(
    occurredAt: at,
    type: type,
    note: 'Logged later, it happened then.',
    attemptedSos: false,
  );

  test('late lean relapse: clean time, best streak and the 3-day milestone '
      'follow occurred time; the milestone is re-earned', () async {
    final (c, store, setNow) = await loaded();
    expect(await c.syncMilestones(), 3);
    expect(c.streak, 4);

    // Logged at day 4, but it happened at day 2.
    await c.recordRelapse(entries: [entry(day(2), RelapseType.fullLean)]);
    expect(c.lastDose, day(2));
    expect(c.streak, 2);
    expect(
      c.longestStreak,
      2,
      reason: 'corrected 3-day milestone must not count',
    );
    final three = milestones(c).single;
    expect(three.metadata[milestoneCorrectedKey], isTrue);
    expect(milestoneCounts(three), isFalse);
    final relapse = c.events.lastWhere(
      (e) => e.type == RecoveryEventType.relapse,
    );
    expect(three.metadata[milestoneCorrectedByKey], relapse.id);

    // Re-earn in the new streak.
    setNow(day(5.1));
    await c.syncMilestones();
    final ms = milestones(c);
    expect(ms.map((e) => e.metadata['days']), [3, 3]);
    expect(ms.map(milestoneCounts), [false, true]);
    expect(ms.last.timestamp, day(5));
    expect(c.longestStreak, 3);

    // Reload: flags persisted, nothing rewritten.
    final writes = store.writes;
    final reloaded = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
      now: () => day(5.1),
    );
    await reloaded.load();
    expect(milestones(reloaded).map(milestoneCounts), [false, true]);
    expect(store.writes, writes);
    expect(await reloaded.syncMilestones(), isNull);
  });

  test(
    'late benzo-only relapse leaves the lean timer and milestones alone',
    () async {
      final (c, _, _) = await loaded();
      await c.syncMilestones();
      await c.recordRelapse(entries: [entry(day(2), RelapseType.benzo)]);
      expect(c.lastDose, start);
      expect(c.streak, 4);
      expect(milestoneCounts(milestones(c).single), isTrue);
      expect(c.longestStreak, 4);
      final benzo = c.events.lastWhere(
        (e) => e.type == RecoveryEventType.relapse,
      );
      expect(benzo.metadata['relapseType'], 'benzo');
    },
  );

  test('editing the relapse to benzo-only restores the milestone; '
      'deleting it does too', () async {
    final (c, _, _) = await loaded();
    await c.syncMilestones();
    await c.recordRelapse(entries: [entry(day(2), RelapseType.fullLean)]);
    final relapse = c.events.lastWhere(
      (e) => e.type == RecoveryEventType.relapse,
    );
    expect(milestoneCounts(milestones(c).single), isFalse);

    await c.editEventMetadata(
      id: relapse.id,
      metadata: {...relapse.metadata, 'relapseType': 'benzo'},
    );
    expect(milestoneCounts(milestones(c).single), isTrue);
    expect(c.lastDose, start);

    await c.editEventMetadata(
      id: relapse.id,
      metadata: {...relapse.metadata, 'relapseType': 'fullLean'},
    );
    expect(milestoneCounts(milestones(c).single), isFalse);

    await c.deleteEvent(id: relapse.id);
    expect(milestoneCounts(milestones(c).single), isTrue);
    expect(c.longestStreak, 4);
  });

  test(
    'an imported backup with an earlier relapse corrects milestones',
    () async {
      final (c, _, _) = await loaded();
      await c.syncMilestones();
      final imported = RecoveryEvent.create(
        type: RecoveryEventType.relapse,
        timestamp: day(1.5),
        metadata: {'relapseType': 'partial', 'streakLost': 1},
      );
      await c.mergeImportedEvents([imported]);
      expect(c.lastDose, day(1.5));
      expect(milestoneCounts(milestones(c).single), isFalse);
      expect(
        milestones(c).single.metadata[milestoneCorrectedByKey],
        imported.id,
      );
    },
  );

  test('a stored state with a stale milestone is reconciled on load', () async {
    final stale = RecoveryEvent.create(
      type: RecoveryEventType.milestone,
      timestamp: day(3),
      metadata: {'days': 3, 'label': 'BREAK THE LOOP', 'source': 'auto'},
    );
    final late = RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      timestamp: day(2),
      metadata: {
        'relapseType': 'fullLean',
        'streakLost': 2,
        'recordedAt': day(4).toIso8601String(),
      },
    );
    final (c, store, _) = await loaded(extra: [stale, late]);
    expect(milestoneCounts(milestones(c).single), isFalse);
    expect(c.longestStreak, 2);
    expect(store.writes, 1, reason: 'the correction is saved once');
  });
}
