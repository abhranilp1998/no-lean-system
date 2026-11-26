import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recap/domain/weekly_recap.dart';
import 'package:no_lean/features/recovery/domain/event_derived_state.dart';

import '../../support/recap_events.dart';

void main() {
  // Friday 27 Nov 2026, 8 PM. The window is Sat 21 Nov to Fri 27 Nov.
  final now = DateTime(2026, 11, 27, 20);

  WeeklyRecap recap(List events, {double spend = 0, DateTime? lastDose}) =>
      computeWeeklyRecap(
        events: events.cast(),
        lastDose: lastDose ?? computeLastDose(events.cast()),
        now: now,
        dailySpend: spend,
      );

  test('a clean week with cravings ridden out is warm and counted', () {
    final events = [
      startAt(DateTime(2026, 10, 1)),
      cravingAt(DateTime(2026, 11, 22, 21, 10)),
      cravingAt(DateTime(2026, 11, 24, 22, 0), intensity: 8),
      cravingAt(DateTime(2026, 11, 25, 20, 30), intensity: 4),
      recheckAt(DateTime(2026, 11, 22, 21, 30), 'gone'),
      recheckAt(DateTime(2026, 11, 24, 22, 20), 'same'),
      sosDoneAt(DateTime(2026, 11, 25, 20, 40)),
    ];
    final r = recap(events);
    expect(r.daysCovered, 7);
    expect(r.cleanDays, 7);
    expect(r.slips, 0);
    expect(r.cravings, 3);
    expect(r.peakIntensity, 8);
    expect(r.averageIntensity, closeTo(6, .01));
    expect(r.peakBand?.label, '9 PM–12 AM');
    expect(r.peakBandCount, 2);
    expect(r.cravingsRiddenOut, 2); // one eased/gone recheck + one SOS
    expect(r.headline, 'A clean week. That is real.');
    expect(r.streakDays, greaterThanOrEqualTo(56));
    expect(r.nextStep, contains('9 PM–12 AM'));
    expect(r.lines.join(' '), contains('7 days clean'));
  });

  test('a slip lowers clean days, resets the streak, and stays kind', () {
    final events = [
      startAt(DateTime(2026, 10, 1)),
      relapseAt(DateTime(2026, 11, 24, 23)),
    ];
    final r = recap(events);
    expect(r.slips, 1);
    expect(r.slipDays, 1);
    expect(r.cleanDays, 6);
    expect(r.streakDays, 2);
    expect(r.headline, contains('Mostly clean'));
    expect(r.lines.join(' '), contains('information, not a verdict'));
    expect(r.nextStep, contains('tonight'));
  });

  test('benzo-only use is logged separately and never counts as a slip', () {
    final events = [
      startAt(DateTime(2026, 10, 1)),
      relapseAt(DateTime(2026, 11, 23, 22), type: 'benzo'),
      relapseAt(DateTime(2026, 11, 25, 22), type: 'benzo'),
    ];
    final r = recap(events);
    expect(r.slips, 0);
    expect(r.benzoOnlyEntries, 2);
    expect(r.cleanDays, 7);
    expect(r.streakDays, greaterThan(50));
    expect(r.lines.join(' '), contains('does not reset your lean timer'));
  });

  test('three or more benzo entries point to the doctor or SOS contact', () {
    final events = [
      startAt(DateTime(2026, 10, 1)),
      for (var d = 22; d < 25; d++)
        relapseAt(DateTime(2026, 11, d, 22), type: 'benzo'),
    ];
    final r = recap(events);
    expect(r.nextStep, contains('doctor or your SOS contact'));
    expect(r.nextStep, isNot(contains('112')));
    expect(r.nextStep.toLowerCase(), isNot(contains('helpline')));
  });

  test('mixed lean + alcohol resets the timer like any lean slip', () {
    final r = recap([
      startAt(DateTime(2026, 10, 1)),
      relapseAt(DateTime(2026, 11, 26, 20), type: 'leanPlusAlcohol'),
    ]);
    expect(r.slips, 1);
  });

  test('a new user only counts days since tracking began', () {
    final r = recap([startAt(DateTime(2026, 11, 25, 9))]);
    expect(r.daysCovered, 3);
    expect(r.cleanDays, 3);
  });

  test('money kept needs a spend, and counts only clean time', () {
    final events = [startAt(DateTime(2026, 10, 1))];
    expect(recap(events).moneyKept, isNull);
    final r = recap(events, spend: 100);
    // 6 whole days + 8/24 of today.
    expect(r.moneyKept, closeTo(100 * (6 + 20 / 24), .5));
    final slipped = recap([
      ...events,
      relapseAt(DateTime(2026, 11, 23, 22)),
    ], spend: 100);
    expect(slipped.moneyKept, lessThan(r.moneyKept!));
  });

  test('a quiet week still returns a gentle next step', () {
    final r = recap([startAt(DateTime(2026, 10, 1))]);
    expect(r.hasAnyActivity, isFalse);
    expect(r.cravings, 0);
    expect(r.nextStep, contains('reason'));
  });

  test('events outside the 7 days are ignored', () {
    final r = recap([
      startAt(DateTime(2026, 9, 1)),
      relapseAt(DateTime(2026, 11, 10)),
      cravingAt(DateTime(2026, 11, 12, 21)),
    ]);
    expect(r.slips, 0);
    expect(r.cravings, 0);
  });

  test('one craving is not called a peak time', () {
    final r = recap([
      startAt(DateTime(2026, 10, 1)),
      cravingAt(DateTime(2026, 11, 22, 21)),
      cravingAt(DateTime(2026, 11, 23, 8)),
    ]);
    expect(r.peakBand, isNull);
  });

  test('time bands read naturally', () {
    expect(const TimeBand(18).label, '6–9 PM');
    expect(const TimeBand(21).label, '9 PM–12 AM');
    expect(const TimeBand(0).label, '12–3 AM');
    expect(const TimeBand(9).label, '9 AM–12 PM');
  });
}
