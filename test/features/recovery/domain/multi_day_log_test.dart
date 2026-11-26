import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/dose_units.dart';
import 'package:no_lean/features/recovery/domain/multi_day_log.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';

void main() {
  final now = DateTime(2026, 11, 26, 18, 30);

  test('slots drop future days, de-duplicate and sort', () {
    final slots = buildMultiDaySlots([
      DateTime(2026, 11, 24, 3),
      DateTime(2026, 11, 22),
      DateTime(2026, 11, 24, 23),
      DateTime(2026, 11, 27),
    ], now: now);
    expect(slots.map((s) => s.occurredAt), [
      DateTime(2026, 11, 22, multiDayDefaultHour),
      DateTime(2026, 11, 24, multiDayDefaultHour),
    ]);
  });

  test('today at a later time is moved back to now, never the future', () {
    final slots = buildMultiDaySlots([now], now: now, hour: 22, minute: 0);
    expect(slots.single.occurredAt, DateTime(2026, 11, 26, 18, 30));
    final early = buildMultiDaySlots([now], now: now, hour: 9, minute: 15);
    expect(early.single.occurredAt, DateTime(2026, 11, 26, 9, 15));
  });

  test('last N days ends today, oldest first', () {
    expect(lastDays(3, now: now), [
      DateTime(2026, 11, 24),
      DateTime(2026, 11, 25),
      DateTime(2026, 11, 26),
    ]);
    expect(lastDays(2, now: DateTime(2026, 3, 1), includeToday: false), [
      DateTime(2026, 2, 27),
      DateTime(2026, 2, 28),
    ]);
  });

  test('one shared entry expands to one entry per day', () {
    final template = RelapseLogEntry(
      occurredAt: now,
      type: RelapseType.partial,
      note: 'Missed days, same pattern each night.',
      attemptedSos: false,
      contextTags: const ['Stress'],
      cost: 120,
    );
    final slots = buildMultiDaySlots(lastDays(3, now: now), now: now);
    final entries = expandMultiDayEntries(template, slots);
    expect(entries, hasLength(3));
    expect(entries.map((e) => e.occurredAt).toSet(), hasLength(3));
    for (final e in entries) {
      expect(e.toMetadata(), template.toMetadata());
    }
  });

  test('only benzo-only saves leave the lean timer alone', () {
    RelapseLogEntry e(RelapseType t) => RelapseLogEntry(
      occurredAt: now,
      type: t,
      note: 'Twelve chars at least',
      attemptedSos: false,
    );
    expect(entriesResetLeanTimer([e(RelapseType.benzo)]), isFalse);
    expect(
      entriesResetLeanTimer([e(RelapseType.benzo), e(RelapseType.fullLean)]),
      isTrue,
    );
    expect(entriesResetLeanTimer([e(RelapseType.leanPlusAlcohol)]), isTrue);
  });

  test('pickable days exclude the future and pre-2000', () {
    expect(isPickableDay(DateTime(2026, 11, 26, 23, 59), now: now), isTrue);
    expect(isPickableDay(DateTime(2026, 11, 27), now: now), isFalse);
    expect(isPickableDay(DateTime(1999, 12, 31), now: now), isFalse);
  });

  group('several doses per day', () {
    final day = DateTime(2026, 11, 20);
    MultiDaySlot at(int h, [int m = 0, DateTime? d]) =>
        MultiDaySlot(day: d ?? day, hour: h, minute: m);

    test('default times spread evenly from 9 AM to 9 PM', () {
      expect(defaultDoseMinutes(1), [21 * 60]);
      expect(defaultDoseMinutes(2), [9 * 60, 21 * 60]);
      expect(defaultDoseMinutes(3), [9 * 60, 15 * 60, 21 * 60]);
      expect(defaultDoseMinutes(5), [
        9 * 60,
        12 * 60,
        15 * 60,
        18 * 60,
        21 * 60,
      ]);
      for (var n = 1; n <= multiDayMaxDosesPerDay; n++) {
        final times = defaultDoseMinutes(n);
        expect(times.toSet(), hasLength(n), reason: '$n doses are distinct');
        expect([...times]..sort(), times);
      }
    });

    test('today never gets a default time in the future', () {
      // now is 6:30 PM
      final today = DateTime(2026, 11, 26);
      final doses = defaultDosesForDay(today, 3, now: now);
      expect(doses, hasLength(3));
      expect(doses.every((d) => !d.occurredAt.isAfter(now)), isTrue);
      expect(doses.map((d) => d.occurredAt).toSet(), hasLength(3));
      expect(doses.last.occurredAt, now.copyWith(second: 0));
    });

    test('defaults keep per-dose overrides by position', () {
      final carry = [at(21).withOverride(type: RelapseType.benzo), at(22)];
      final doses = defaultDosesForDay(day, 3, now: now, carry: carry);
      expect(doses[0].type, RelapseType.benzo);
      expect(doses[1].type, isNull);
      expect(doses[2].type, isNull);
    });

    test('next dose goes three hours after, or before when past midnight', () {
      expect(nextDoseSlot([at(9)], day, now: now)!.hour, 12);
      expect(nextDoseSlot([at(21)], day, now: now)!.hour, 18);
      expect(nextDoseSlot([at(21), at(18)], day, now: now)!.hour, 15);
      expect(nextDoseSlot(const [], day, now: now)!.hour, 21);
    });

    test('next dose on today stays in the past and times stay unique', () {
      final today = DateTime(2026, 11, 26);
      final slots = [at(16, 0, today)];
      final next = nextDoseSlot(slots, today, now: now)!;
      expect(next.occurredAt.isAfter(now), isFalse);
      expect(next.occurredAt, DateTime(2026, 11, 26, 13));
      expect(firstDuplicateSlot([...slots, next]), isNull);
    });

    test('a day takes at most the per-day maximum', () {
      final full = [for (var i = 0; i < multiDayMaxDosesPerDay; i++) at(i + 1)];
      expect(nextDoseSlot(full, day, now: now), isNull);
    });

    test('identical times on one day are found, other days are fine', () {
      expect(firstDuplicateSlot([at(21), at(9), at(21)]), isNotNull);
      expect(
        firstDuplicateSlot([at(21), at(21, 0, DateTime(2026, 11, 21))]),
        isNull,
      );
      expect(
        timeTakenOnDay([at(9), at(21)], day, 21, 0, ignoreIndex: 1),
        isFalse,
      );
      expect(timeTakenOnDay([at(9), at(21)], day, 21, 0), isTrue);
    });

    test('per-dose overrides replace only that dose', () {
      final template = RelapseLogEntry(
        occurredAt: now,
        type: RelapseType.fullLean,
        note: 'Missed days, same pattern each night.',
        attemptedSos: false,
        quantity: '1 bottle',
        dose: DoseAmount.entered(1, DoseUnit.bottle, bottleMl: 100),
        cost: 120,
      );
      final tablets = DoseAmount.entered(2, DoseUnit.tablet, bottleMl: 100);
      final entries = expandMultiDayEntries(template, [
        at(9),
        at(14).withOverride(type: RelapseType.benzo, dose: tablets),
        at(21),
      ]);
      expect(entries.map((e) => e.occurredAt.hour), [9, 14, 21]);
      expect(entries[0].toMetadata(), template.toMetadata());
      expect(entries[2].toMetadata(), template.toMetadata());
      final own = entries[1].toMetadata();
      expect(own['relapseType'], 'benzo');
      expect(own['unit'], 'tablet');
      expect(own['amount'], 2);
      expect(own.containsKey('quantity'), isFalse);
      expect(own['cost'], 120);
    });

    test('summary reads "5 entries across 3 days"', () {
      final d2 = DateTime(2026, 11, 21);
      final d3 = DateTime(2026, 11, 22);
      expect(
        multiDayEntrySummary([
          at(9),
          at(21),
          at(9, 0, d2),
          at(21, 0, d2),
          at(21, 0, d3),
        ]),
        '5 entries across 3 days',
      );
      expect(multiDayEntrySummary([at(21)]), '1 entry across 1 day');
    });

    test('slots keep their overrides when the time changes', () {
      final s = at(9).withOverride(type: RelapseType.alcohol).withTime(10, 5);
      expect(s.type, RelapseType.alcohol);
      expect((s.hour, s.minute), (10, 5));
    });
  });
}
