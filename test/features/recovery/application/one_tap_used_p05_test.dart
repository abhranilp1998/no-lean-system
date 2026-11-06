import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/double_tap.dart';
import 'package:no_lean/features/recovery/domain/milestones.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/presentation/relapse_log_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<RecoveryEvent> relapses(RecoveryController c) =>
      c.events.where((e) => e.type == RecoveryEventType.relapse).toList();

  test('one-tap Used logs now; a double-tap is absorbed', () async {
    final c = RecoveryController(relapseLock: FakeRelapseLock());
    await c.load();
    final before = relapses(c).length;
    final results = await Future.wait([c.quickLogUsed(), c.quickLogUsed()]);
    await c.quickLogUsed();
    expect(results, everyElement(ProtectedActionResult.completed));
    final after = relapses(c);
    expect(after.length, before + 1);
    expect(after.last.metadata['quick'], isTrue);
    expect(after.last.metadata['recordedAt'], isA<String>());
  });

  test('backfill keeps occurredAt and recordedAt separate', () async {
    final c = RecoveryController(relapseLock: FakeRelapseLock());
    await c.load();
    final at = relapseHoursAgo(3);
    await c.recordRelapse(occurredAt: [at], operationId: 'op-1');
    // Same idempotency key again (e.g. double-tap on SAVE) adds nothing.
    await c.recordRelapse(occurredAt: [at], operationId: 'op-1');
    final logged = relapses(c).where((e) => e.metadata['batchId'] == 'op-1');
    expect(logged, hasLength(1));
    final recordedAt = DateTime.parse(logged.single.metadata['recordedAt']);
    expect(logged.single.timestamp, at);
    expect(recordedAt.difference(at).inMinutes, greaterThanOrEqualTo(179));
  });

  test('bulk backfill of several past relapses at once', () async {
    final c = RecoveryController(relapseLock: FakeRelapseLock());
    await c.load();
    final before = relapses(c).length;
    await c.recordRelapse(
      occurredAt: [relapseHoursAgo(12), relapseHoursAgo(6), relapseHoursAgo(1)],
    );
    expect(relapses(c).length, before + 3);
  });

  test('backfilled relapse never re-triggers milestone celebrations', () async {
    final c = RecoveryController(relapseLock: FakeRelapseLock());
    await c.load();
    // Logged now, but it happened 3 days ago: day-1 (and 3) are only reached
    // on paper and must stay quiet.
    await c.recordRelapse(
      occurredAt: [DateTime.now().subtract(const Duration(days: 3, hours: 1))],
    );
    final reached = await c.syncMilestones();
    expect(reached, isNull);
    expect(c.pendingCelebration, isNull);
    final silent = c.events.where(
      (e) =>
          e.type == RecoveryEventType.milestone &&
          e.timestamp.isAfter(c.lastDose.subtract(const Duration(seconds: 1))),
    );
    expect(silent, isNotEmpty);
    expect(silent.every((e) => e.metadata['backfilled'] == true), isTrue);
  });

  test('milestoneIsBackfilled is pure and time-based', () {
    final dose = DateTime(2026, 11, 1);
    final m = recoveryMilestones.first;
    final reach = dose.add(Duration(days: m.days));
    expect(
      milestoneIsBackfilled(
        milestone: m,
        lastDose: dose,
        resetRecordedAt: reach.add(const Duration(hours: 1)),
      ),
      isTrue,
    );
    expect(
      milestoneIsBackfilled(
        milestone: m,
        lastDose: dose,
        resetRecordedAt: reach.subtract(const Duration(hours: 1)),
      ),
      isFalse,
    );
    expect(
      milestoneIsBackfilled(
        milestone: m,
        lastDose: dose,
        resetRecordedAt: null,
      ),
      isFalse,
    );
  });

  test('out-of-order backfills still never celebrate', () async {
    final c = RecoveryController(relapseLock: FakeRelapseLock());
    await c.load();
    await c.recordRelapse(
      occurredAt: [DateTime.now().subtract(const Duration(days: 3, hours: 1))],
    );
    await c.syncMilestones();
    // An even older relapse saved afterwards must not change the streak's
    // reset or wake any milestone.
    await c.recordRelapse(
      occurredAt: [DateTime.now().subtract(const Duration(days: 8))],
    );
    expect(await c.syncMilestones(), isNull);
    expect(c.pendingCelebration, isNull);
    final m = c.events.where((e) => e.type == RecoveryEventType.milestone);
    expect(m.every((e) => e.metadata['backfilled'] == true), isTrue);
  });

  test('a live relapse does not mark future milestones as backfilled', () {
    final now = DateTime(2026, 11, 4, 20);
    for (final m in recoveryMilestones) {
      expect(
        milestoneIsBackfilled(
          milestone: m,
          lastDose: now,
          resetRecordedAt: now,
        ),
        isFalse,
      );
    }
  });

  test('every entry of a multi-entry save shares one batchId', () async {
    final c = RecoveryController(relapseLock: FakeRelapseLock());
    await c.load();
    await c.recordRelapse(occurredAt: [relapseHoursAgo(6), relapseHoursAgo(2)]);
    await c.quickLogUsed();
    final r = relapses(c);
    final multi = r.sublist(r.length - 3, r.length - 1);
    expect(multi.map((e) => e.metadata['batchId']).toSet(), hasLength(1));
    expect(multi.first.metadata['batchId'], isA<String>());
    expect(r.last.metadata['batchId'], isNot(multi.first.metadata['batchId']));
  });

  group('shared double-tap rule', () {
    final t = DateTime(2026, 10, 6, 18, 44, 32);
    RecoveryEvent ev(
      RecoveryEventType type,
      DateTime at, {
      Map<String, dynamic> m = const {},
    }) => RecoveryEvent.fromJson({
      'id': '${type.name}-${at.millisecondsSinceEpoch}-${m.hashCode}',
      'type': type.name,
      'timestamp': at.toIso8601String(),
      'metadata': m,
    });
    test('identical cravings 3 s apart are a double-tap', () {
      final m = {'intensity': 5, 'trigger': 'stress', 'note': ''};
      expect(
        isDoubleTap(
          ev(RecoveryEventType.craving, t, m: m),
          ev(
            RecoveryEventType.craving,
            t.add(const Duration(seconds: 3)),
            m: m,
          ),
        ),
        isTrue,
      );
    });
    test('same batch, pledges and blank-note backfills are never touched', () {
      final rec = t.toIso8601String();
      expect(
        isDoubleTap(
          ev(
            RecoveryEventType.relapse,
            t,
            m: {'recordedAt': rec, 'note': 'x', 'batchId': 'b'},
          ),
          ev(
            RecoveryEventType.relapse,
            t,
            m: {'recordedAt': rec, 'note': 'x', 'batchId': 'b'},
          ),
        ),
        isFalse,
      );
      expect(
        isDoubleTap(
          ev(RecoveryEventType.pledge, t),
          ev(RecoveryEventType.pledge, t),
        ),
        isFalse,
      );
      final past = t.subtract(const Duration(hours: 3));
      expect(
        isDoubleTap(
          ev(
            RecoveryEventType.relapse,
            past,
            m: {'recordedAt': rec, 'batchId': 'a'},
          ),
          ev(
            RecoveryEventType.relapse,
            past,
            m: {'recordedAt': rec, 'batchId': 'b'},
          ),
        ),
        isFalse,
      );
    });
    test('outside the window is not a double-tap', () {
      final m = {'intensity': 5, 'trigger': 'stress'};
      expect(
        isDoubleTap(
          ev(RecoveryEventType.craving, t, m: m),
          ev(RecoveryEventType.craving, t.add(doubleTapWindow * 2), m: m),
        ),
        isFalse,
      );
    });
  });

  test('relapseHoursAgo rounds to the minute, never future', () {
    final now = DateTime(2026, 11, 4, 22, 30, 45);
    expect(relapseHoursAgo(2, now: now), DateTime(2026, 11, 4, 20, 30));
  });
}
