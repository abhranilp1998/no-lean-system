import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/utils/formatters.dart';
import 'package:no_lean/features/recovery/domain/event_derived_state.dart';
import 'package:no_lean/features/recovery/domain/money_saved.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

RecoveryEvent relapse({
  required DateTime at,
  required String type,
  double? cost,
}) => RecoveryEvent.create(
  type: RecoveryEventType.relapse,
  timestamp: at,
  metadata: {'relapseType': type, 'cost': ?cost},
);

void main() {
  final start = DateTime(2026, 10, 1, 12);
  const eighteen = Duration(days: 18);

  test('daily spend times clean days matches the existing counter', () {
    final snap = computeMoneySaved(
      dailySpend: 120,
      bottleMl: 100,
      cleanDuration: eighteen,
      events: const [],
      lastDose: start,
    );
    expect(snap.moneySaved, 18 * 120);
    expect(snap.grossSaved, 2160);
    expect(snap.isSpendSet, isTrue);
    expect(snap.format(snap.moneySaved), contains('₹'));
  });

  test('per-bottle price and usual daily ml derive the daily rate', () {
    // 50 ml/day at ₹240 per 100 ml bottle → ₹120/day
    final snap = computeMoneySaved(
      dailySpend: 0,
      bottleMl: 100,
      spendPerBottle: 240,
      usualDailyMl: 50,
      cleanDuration: eighteen,
      events: const [],
      lastDose: start,
    );
    expect(snap.dailySpend, 120);
    expect(snap.moneySaved, 2160);
    expect(snap.hasBreakdown, isTrue);
    expect(snap.warmCopy, contains('₹120'));
    expect(snap.warmCopy, contains('18 days'));
    expect(snap.warmCopy.toLowerCase(), contains('bottle'));
  });

  test('legacy dailySpend is used when the breakdown is missing', () {
    final snap = computeMoneySaved(
      dailySpend: 450,
      bottleMl: 100,
      cleanDuration: const Duration(days: 2),
      events: const [],
      lastDose: start,
    );
    expect(snap.moneySaved, 900);
    expect(snap.hasBreakdown, isFalse);
  });

  test('benzo-only costs after lastDose can be subtracted', () {
    final benzo = relapse(
      at: start.add(const Duration(days: 3)),
      type: 'benzo',
      cost: 500,
    );
    expect(resetsLeanCleanTimer(benzo), isFalse);
    final off = computeMoneySaved(
      dailySpend: 120,
      bottleMl: 100,
      cleanDuration: eighteen,
      events: [benzo],
      lastDose: start,
      subtractOtherCosts: true,
    );
    expect(off.otherCosts, 500);
    expect(off.moneySaved, 2160 - 500);
    expect(off.warmCopy, contains('₹500'));
    expect(off.warmCopy, contains('₹1,660'));

    final raw = computeMoneySaved(
      dailySpend: 120,
      bottleMl: 100,
      cleanDuration: eighteen,
      events: [benzo],
      lastDose: start,
    );
    expect(raw.moneySaved, 2160);
    expect(raw.otherCosts, 0);
  });

  test('a lean slip at lastDose is not subtracted from this streak', () {
    final lean = relapse(at: start, type: 'fullLean', cost: 400);
    expect(resetsLeanCleanTimer(lean), isTrue);
    final snap = computeMoneySaved(
      dailySpend: 120,
      bottleMl: 100,
      cleanDuration: eighteen,
      events: [
        lean,
        relapse(
          at: start.add(const Duration(days: 2)),
          type: 'benzo',
          cost: 80,
        ),
      ],
      lastDose: start,
      subtractOtherCosts: true,
    );
    expect(snap.otherCosts, 80);
    expect(snap.moneySaved, 2160 - 80);
  });

  test(
    'alcohol after the timer start is ignored because it would reset it',
    () {
      final alcohol = relapse(
        at: start.add(const Duration(days: 1)),
        type: 'alcohol',
        cost: 200,
      );
      expect(resetsLeanCleanTimer(alcohol), isTrue);
      final snap = computeMoneySaved(
        dailySpend: 100,
        bottleMl: 100,
        cleanDuration: eighteen,
        events: [alcohol],
        lastDose: start,
        subtractOtherCosts: true,
      );
      expect(snap.otherCosts, 0);
      expect(snap.moneySaved, 1800);
    },
  );

  test('net total never goes below zero', () {
    final snap = computeMoneySaved(
      dailySpend: 10,
      bottleMl: 100,
      cleanDuration: const Duration(days: 1),
      events: [
        relapse(
          at: start.add(const Duration(hours: 1)),
          type: 'benzo',
          cost: 500,
        ),
      ],
      lastDose: start,
      subtractOtherCosts: true,
    );
    expect(snap.moneySaved, 0);
  });

  test('unset spend yields a gentle prompt and zero saved', () {
    final snap = computeMoneySaved(
      dailySpend: 0,
      bottleMl: 100,
      cleanDuration: eighteen,
      events: const [],
      lastDose: start,
    );
    expect(snap.isSpendSet, isFalse);
    expect(snap.moneySaved, 0);
    expect(snap.warmCopy.toLowerCase(), contains('usual day'));
    expect(snap.homeDetail.toLowerCase(), contains('tap'));
  });

  test('goal jar percent is floored and can exceed 100', () {
    final snap = computeMoneySaved(
      dailySpend: 120,
      bottleMl: 100,
      cleanDuration: eighteen,
      events: const [],
      lastDose: start,
      goal: const SavingsGoal(name: 'New phone', target: 4000),
    );
    expect(snap.goalPercent, 54); // 2160/4000 = 0.54
    expect(snap.warmCopy, contains('New phone'));
    expect(snap.warmCopy, contains('54%'));

    final done = computeMoneySaved(
      dailySpend: 200,
      bottleMl: 100,
      cleanDuration: const Duration(days: 30),
      events: const [],
      lastDose: start,
      goal: const SavingsGoal(name: 'New phone', target: 4000),
    );
    expect(done.moneySaved, 6000);
    expect(done.goalPercent, 150);
    expect(done.warmCopy.toLowerCase(), contains('you made it'));
  });

  test('selected currency appears in copy; widget text names no substance', () {
    final snap = computeMoneySaved(
      dailySpend: 20,
      bottleMl: 100,
      cleanDuration: const Duration(days: 3),
      events: const [],
      lastDose: start,
      currency: AppCurrency.usd,
      goal: const SavingsGoal(name: 'Headphones', target: 100),
    );
    expect(snap.format(60), contains(r'$'));
    expect(snap.widgetKept.toLowerCase(), contains('kept'));
    expect(isPrivacySafeMoneyCopy(snap.widgetKept), isTrue);
    expect(isPrivacySafeMoneyCopy(snap.notificationText), isTrue);
    expect(snap.notificationText.toLowerCase(), isNot(contains('lean')));
    expect(snap.notificationText.toLowerCase(), isNot(contains('codeine')));
  });

  test('SavingsGoal.tryParse is lenient and rejects junk', () {
    expect(SavingsGoal.tryParse(null), isNull);
    expect(SavingsGoal.tryParse('nope'), isNull);
    expect(SavingsGoal.tryParse({'name': '', 'target': 10}), isNull);
    expect(SavingsGoal.tryParse({'name': 'X', 'target': 0}), isNull);
    expect(SavingsGoal.tryParse({'name': 'X', 'target': -5}), isNull);
    final ok = SavingsGoal.tryParse({
      'name': '  Trip  ',
      'target': 1500,
      'photoPath': '/tmp/pic.jpg',
    });
    expect(ok, isNotNull);
    expect(ok!.name, 'Trip');
    expect(ok.target, 1500);
    expect(ok.photoPath, '/tmp/pic.jpg');
    expect(ok.toJson()['name'], 'Trip');
  });

  test('typicalDailySpend rejects incomplete or invalid inputs', () {
    expect(
      typicalDailySpend(spendPerBottle: 100, usualDailyMl: 50, bottleMl: 100),
      50,
    );
    expect(
      typicalDailySpend(spendPerBottle: 0, usualDailyMl: 50, bottleMl: 100),
      0,
    );
    expect(
      typicalDailySpend(spendPerBottle: 100, usualDailyMl: null, bottleMl: 100),
      isNull,
    );
    expect(
      typicalDailySpend(spendPerBottle: 100, usualDailyMl: 50, bottleMl: 1),
      isNull,
    );
  });

  test('default money() still formats rupees so existing call sites hold', () {
    expect(money(2160), contains('₹'));
    expect(money(2160), contains('2,160'));
  });
}
