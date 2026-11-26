import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/event_derived_state.dart';
import 'package:no_lean/features/recovery/domain/milestones.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/streak_wording.dart';

/// Late (backdated) relapse logging: clean time follows *occurred* time.
void main() {
  final start = DateTime(2026, 10, 1, 9);
  DateTime day(num d) => start.add(Duration(minutes: (d * 24 * 60).round()));

  RecoveryEvent baseline() => RecoveryEvent.create(
    type: RecoveryEventType.recoveryStart,
    timestamp: start,
  );
  RecoveryEvent milestone(int days, {DateTime? at}) => RecoveryEvent.create(
    type: RecoveryEventType.milestone,
    timestamp: at ?? day(days),
    metadata: {
      'days': days,
      'label': milestoneFor(days)?.label ?? '',
      'source': 'auto',
    },
  );
  RecoveryEvent relapse(
    num atDay, {
    String? type,
    int? streakLost,
    DateTime? recordedAt,
  }) => RecoveryEvent.create(
    type: RecoveryEventType.relapse,
    timestamp: day(atDay),
    metadata: {
      'relapseType': ?type,
      'streakLost': ?streakLost,
      'recordedAt': ?recordedAt?.toIso8601String(),
    },
  );
  RecoveryEvent byType(List<RecoveryEvent> events, int days) => events
      .where(
        (e) =>
            e.type == RecoveryEventType.milestone && e.metadata['days'] == days,
      )
      .single;

  group('reconcileMilestones', () {
    test('a backdated lean relapse marks later milestones corrected, '
        'never deleted', () {
      final r = relapse(2, recordedAt: day(8), streakLost: 2);
      final events = [baseline(), milestone(3), milestone(7), r];
      final out = reconcileMilestones(events);

      expect(out, hasLength(events.length));
      for (final days in [3, 7]) {
        final m = byType(out, days);
        expect(m.metadata[milestoneCorrectedKey], isTrue);
        expect(
          m.metadata[milestoneCorrectedReasonKey],
          milestoneCorrectedRelapse,
        );
        expect(m.metadata[milestoneCorrectedByKey], r.id);
        expect(milestoneCounts(m), isFalse);
      }
    });

    test('milestones reached before the relapse stay valid', () {
      final events = [baseline(), milestone(3), relapse(5, streakLost: 5)];
      final out = reconcileMilestones(events);
      expect(milestoneCounts(byType(out, 3)), isTrue);
      expect(
        byType(out, 3).metadata.containsKey(milestoneCorrectedKey),
        isFalse,
      );
    });

    test('is idempotent: same list back when nothing changes', () {
      final events = reconcileMilestones([
        baseline(),
        milestone(3),
        relapse(2, streakLost: 2),
      ]);
      expect(identical(reconcileMilestones(events), events), isTrue);
    });

    test(
      'corrected milestones no longer block re-earning in the new streak',
      () {
        final events = reconcileMilestones([
          baseline(),
          milestone(3),
          relapse(2, streakLost: 2),
        ]);
        final lastDose = computeLastDose(events);
        expect(lastDose, day(2));
        expect(
          dueMilestones(
            events: events,
            lastDose: lastDose,
            now: day(5.1),
          ).map((m) => m.days),
          [3],
        );
      },
    );

    test('best streak excludes corrected milestones', () {
      final raw = [
        baseline(),
        milestone(3),
        milestone(7),
        relapse(2, streakLost: 2),
      ];
      // Before the fix the 7-day milestone still counted as best streak.
      expect(computeLongestStreak(raw), 7);
      expect(computeLongestStreak(reconcileMilestones(raw)), 2);
    });

    test('deleting the relapse restores the milestone; a copy re-earned in '
        'the same streak becomes a duplicate', () {
      final r = relapse(2, streakLost: 2);
      final reEarned = milestone(3, at: day(5));
      final withRelapse = reconcileMilestones([
        baseline(),
        milestone(3),
        r,
        reEarned,
      ]);
      expect(
        withRelapse
            .where((e) => e.type == RecoveryEventType.milestone)
            .map(milestoneCounts),
        [false, true],
      );

      final withoutRelapse = reconcileMilestones(
        withRelapse.where((e) => e.id != r.id).toList(),
      );
      final ms = withoutRelapse
          .where((e) => e.type == RecoveryEventType.milestone)
          .toList();
      expect(milestoneCounts(ms[0]), isTrue);
      expect(ms[0].metadata.containsKey(milestoneCorrectedByKey), isFalse);
      expect(milestoneCounts(ms[1]), isFalse);
      expect(
        ms[1].metadata[milestoneCorrectedReasonKey],
        milestoneCorrectedDuplicate,
      );
    });

    test('benzo-only backdated relapse never corrects a lean milestone', () {
      final events = reconcileMilestones([
        baseline(),
        milestone(3),
        milestone(7),
        relapse(2, type: 'benzo', streakLost: 0),
      ]);
      expect(milestoneCounts(byType(events, 3)), isTrue);
      expect(milestoneCounts(byType(events, 7)), isTrue);
      expect(computeLastDose(events), start);
      expect(computeLongestStreak(events), 7);
    });

    test('mixed use with lean still corrects', () {
      final events = reconcileMilestones([
        baseline(),
        milestone(3),
        relapse(2, type: 'benzo'),
        relapse(2, type: 'leanPlusAlcohol'),
      ]);
      expect(milestoneCounts(byType(events, 3)), isFalse);
    });

    test(
      're-typing the relapse as benzo-only (edit) restores the milestone',
      () {
        final r = relapse(2, type: 'fullLean', streakLost: 2);
        final corrected = reconcileMilestones([baseline(), milestone(3), r]);
        expect(milestoneCounts(byType(corrected, 3)), isFalse);
        final edited = [
          for (final e in corrected)
            e.id == r.id
                ? e.copyWith(metadata: {...e.metadata, 'relapseType': 'benzo'})
                : e,
        ];
        expect(milestoneCounts(byType(reconcileMilestones(edited), 3)), isTrue);
      },
    );

    test(
      'streakLost follows occurred time when a relapse is inserted earlier',
      () {
        // Logged in order: relapse at day 6 (6 days lost). Then a relapse at
        // day 2 is logged late, so the day-6 one only ended a 4-day streak.
        final later = relapse(6, streakLost: 6);
        final early = relapse(2, streakLost: 2, recordedAt: day(7));
        final out = reconcileMilestones([baseline(), early, later]);
        final fixed = out.firstWhere((e) => e.id == later.id);
        expect(fixed.metadata['streakLost'], 4);
        expect(fixed.metadata[streakLostRecordedKey], 6);
        expect(
          out.firstWhere((e) => e.id == early.id).metadata['streakLost'],
          2,
        );
      },
    );

    test('legacy relapses with no earlier reset keep their streakLost', () {
      final legacy = RecoveryEvent.create(
        type: RecoveryEventType.relapse,
        timestamp: day(-30),
        metadata: {'streakLost': 40},
      );
      final out = reconcileMilestones([legacy, baseline()]);
      expect(out.first.metadata['streakLost'], 40);
      expect(out.first.metadata.containsKey(streakLostRecordedKey), isFalse);
    });

    test('legacy and manual milestones are left alone', () {
      final legacy = RecoveryEvent.create(
        type: RecoveryEventType.milestone,
        timestamp: day(1),
        metadata: {'days': 30, 'source': 'legacyLongestStreak'},
      );
      final out = reconcileMilestones([baseline(), relapse(0.5), legacy]);
      expect(milestoneCounts(out.last), isTrue);
    });

    test('corrected flags survive a JSON round trip (backup/import)', () {
      final out = reconcileMilestones([baseline(), milestone(3), relapse(2)]);
      final restored = [
        for (final e in out) RecoveryEvent.fromJson(e.toJson()),
      ];
      expect(milestoneCounts(byType(restored, 3)), isFalse);
      expect(identical(reconcileMilestones(restored), restored), isTrue);
    });
  });

  group('interruptedStreakLabel', () {
    test('singular, plural and under a day read naturally', () {
      expect(
        interruptedStreakLabel(relapse(1, streakLost: 1)),
        '1-DAY STREAK INTERRUPTED',
      );
      expect(
        interruptedStreakLabel(relapse(1, streakLost: 8)),
        '8-DAY STREAK INTERRUPTED',
      );
      expect(
        interruptedStreakLabel(relapse(1, streakLost: 0)),
        'STREAK UNDER 1 DAY',
      );
      expect(interruptedStreakLabel(relapse(1)), isNull);
    });

    test('benzo-only never claims it interrupted the lean streak', () {
      expect(
        interruptedStreakLabel(relapse(1, type: 'benzo', streakLost: 5)),
        'LEAN TIMER KEPT',
      );
    });
  });
}
