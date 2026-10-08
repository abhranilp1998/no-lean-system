import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/progress/domain/dose_insights.dart';
import 'package:no_lean/features/progress/domain/money_series.dart';
import 'package:no_lean/features/progress/domain/recovery_insights.dart';
import 'package:no_lean/features/recovery/domain/dose_safety.dart';
import 'package:no_lean/features/recovery/domain/dose_units.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';

final now = DateTime(2026, 10, 9, 20);
var _seq = 0;

RecoveryEvent relapse(
  DateTime at, {
  RelapseType type = RelapseType.fullLean,
  DoseAmount? dose,
  double? cost,
  int? stress,
}) => RecoveryEvent.fromJson({
  'id': 'r${_seq++}',
  'type': 'relapse',
  'timestamp': at.toIso8601String(),
  'metadata': {
    'relapseType': type.name,
    'cost': ?cost,
    'stress': ?stress,
    ...?dose?.toMetadata(),
  },
});

RecoveryEvent craving(DateTime at, int intensity, {int? stress}) =>
    RecoveryEvent.fromJson({
      'id': 'c${_seq++}',
      'type': 'craving',
      'timestamp': at.toIso8601String(),
      'metadata': {
        'intensity': intensity,
        'trigger': 'Habit',
        'stress': ?stress,
      },
    });

DoseAmount ml(double v) => DoseAmount.entered(v, DoseUnit.ml, bottleMl: 100);
DoseAmount bottles(double v, [double size = 100]) =>
    DoseAmount.entered(v, DoseUnit.bottle, bottleMl: size);
DoseAmount tablets(double v) =>
    DoseAmount.entered(v, DoseUnit.tablet, bottleMl: 100);

DateTime daysAgo(int days, [int hour = 21]) =>
    DateTime(now.year, now.month, now.day - days, hour);

void main() {
  group('per-type stats', () {
    test('ml totals never include tablets or drinks', () {
      final stats = relapseTypeStats([
        relapse(daysAgo(5), dose: ml(200), cost: 400),
        relapse(daysAgo(4), dose: bottles(1.5)),
        relapse(daysAgo(3), type: RelapseType.benzo, dose: tablets(2)),
        relapse(daysAgo(2), type: RelapseType.benzo, dose: tablets(1)),
        relapse(daysAgo(1), type: RelapseType.benzo, cost: 150),
      ]);
      final lean = stats.firstWhere((s) => s.type == RelapseType.fullLean);
      expect(lean.count, 2);
      expect(lean.totalMl, 350);
      expect(lean.averageMl, 175);
      expect(lean.realCost, 400);
      final benzo = stats.firstWhere((s) => s.type == RelapseType.benzo);
      expect(benzo.count, 3);
      expect(benzo.totalMl, 0);
      expect(benzo.averageMl, isNull);
      expect(benzo.countTotals, {DoseUnit.tablet: 3});
      expect(benzo.realCost, 150);
      expect(stats.first.type, RelapseType.benzo); // most frequent first
    });
  });

  group('dose escalation', () {
    test('flags a 20%+ rise over the previous average, across ml units', () {
      final escalations = doseEscalations([
        relapse(daysAgo(10), dose: ml(200)),
        relapse(daysAgo(8), dose: bottles(2)), // 200 ml at 100 ml bottles
        relapse(daysAgo(6), dose: ml(200)),
        relapse(
          daysAgo(1),
          dose: DoseAmount.entered(.25, DoseUnit.litre, bottleMl: 100),
        ),
      ], now: now);
      expect(escalations, hasLength(1));
      expect(escalations.single.unitKey, 'ml');
      expect(escalations.single.latest, 250);
      expect(escalations.single.baseline, 200);
      expect(escalations.single.percentUp, 25);
    });

    test('19% is not flagged; fewer than 2 previous doses is not judged', () {
      expect(
        doseEscalations([
          relapse(daysAgo(3), dose: ml(100)),
          relapse(daysAgo(2), dose: ml(100)),
          relapse(daysAgo(1), dose: ml(119)),
        ], now: now),
        isEmpty,
      );
      expect(
        doseEscalations([
          relapse(daysAgo(2), dose: ml(100)),
          relapse(daysAgo(1), dose: ml(500)),
        ], now: now),
        isEmpty,
      );
    });

    test('tablets compare only with tablets, never with ml', () {
      final escalations = doseEscalations([
        relapse(daysAgo(4), type: RelapseType.other, dose: ml(500)),
        relapse(daysAgo(3), type: RelapseType.other, dose: tablets(1)),
        relapse(daysAgo(2), type: RelapseType.other, dose: tablets(1)),
        relapse(daysAgo(1), type: RelapseType.other, dose: tablets(2)),
      ], now: now);
      expect(escalations.single.unitKey, 'tablet');
      expect(escalations.single.percentUp, 100);
    });

    test('types are compared separately', () {
      expect(
        doseEscalations([
          relapse(daysAgo(3), dose: ml(100)),
          relapse(daysAgo(2), dose: ml(100)),
          relapse(daysAgo(1), type: RelapseType.alcohol, dose: ml(500)),
        ], now: now),
        isEmpty,
      );
    });

    test('a later bottle-size change does not fake an escalation', () {
      // Two bottles at 100 ml, then the user switches to 250 ml bottles and
      // logs one bottle: 250 ml vs 200 ml avg is a real 25% rise in ml.
      final escalations = doseEscalations([
        relapse(daysAgo(3), dose: bottles(2)),
        relapse(daysAgo(2), dose: bottles(2)),
        relapse(daysAgo(1), dose: bottles(1, 250)),
      ], now: now);
      expect(escalations.single.latest, 250);
      expect(escalations.single.baseline, 200);
    });
  });

  test('same-day repeats count days with 2+ relapses', () {
    final repeats = sameDayRepeats([
      relapse(daysAgo(2, 14), dose: ml(100)),
      relapse(daysAgo(2, 22), dose: ml(150)),
      relapse(daysAgo(5), dose: ml(100)),
      relapse(daysAgo(40, 10)),
      relapse(daysAgo(40, 11)), // outside 30 days
    ], now: now);
    expect(repeats, hasLength(1));
    expect(repeats.single.count, 2);
    expect(repeats.single.totalMl, 250);
  });

  group('high need', () {
    test('stress 5 or two stress 4+ logs in 48 h', () {
      expect(
        highNeedSignal([craving(daysAgo(1), 6, stress: 5)], now: now)!.reasons,
        ['stress logged at 5/5'],
      );
      expect(
        highNeedSignal([
          craving(daysAgo(1), 6, stress: 4),
          relapse(daysAgo(0, 10), stress: 4),
        ], now: now)!.reasons,
        ['2 logs at stress 4+'],
      );
      expect(
        highNeedSignal([craving(daysAgo(1), 6, stress: 4)], now: now),
        isNull,
      );
      expect(
        highNeedSignal([craving(daysAgo(3), 6, stress: 5)], now: now),
        isNull,
      );
    });

    test('stress 4 plus a stronger recheck', () {
      final c = craving(daysAgo(1), 6, stress: 4);
      final check = RecoveryEvent.fromJson({
        'id': 'k',
        'type': 'cravingCheck',
        'timestamp': daysAgo(1, 22).toIso8601String(),
        'metadata': {'cravingId': c.id, 'intensity': 8, 'outcome': 'stronger'},
      });
      expect(highNeedSignal([c, check], now: now)!.reasons, [
        '1 craving got stronger on recheck',
      ]);
    });
  });

  test('stress-intensity pattern needs 3 each and a 1.2x gap', () {
    final events = [
      for (var i = 0; i < 3; i++) craving(daysAgo(i + 1), 8, stress: 5),
      for (var i = 0; i < 3; i++) craving(daysAgo(i + 5), 4, stress: 1),
    ];
    final pattern = stressIntensityPattern(events)!;
    expect(pattern.highAverage, 8);
    expect(pattern.lowAverage, 4);
    expect(stressIntensityPattern(events.take(5)), isNull);
  });

  group('logging safety warnings', () {
    test('mixing across the draft and the last 24 hours', () {
      final warnings = loggingSafetyWarnings(
        draft: [(type: RelapseType.alcohol, at: now)],
        events: [relapse(now.subtract(const Duration(hours: 5)))],
        cleanStreakDays: 0,
        now: now,
      );
      expect(warnings.map((w) => w.kind), contains(DoseWarningKind.mixing));
      expect(warnings.first.body, contains('codeine/lean + alcohol'));
      expect(
        loggingSafetyWarnings(
          draft: [(type: RelapseType.leanPlusAlcohol, at: now)],
          events: const [],
          cleanStreakDays: 0,
          now: now,
        ).single.kind,
        DoseWarningKind.mixing,
      );
      expect(
        loggingSafetyWarnings(
          draft: [(type: RelapseType.fullLean, at: now)],
          events: [relapse(now.subtract(const Duration(days: 3)))],
          cleanStreakDays: 0,
          now: now,
        ),
        isEmpty,
      );
    });

    test('repeat dose same day and tolerance after 3+ clean days', () {
      final warnings = loggingSafetyWarnings(
        draft: [(type: RelapseType.fullLean, at: now)],
        events: [relapse(DateTime(now.year, now.month, now.day, 9))],
        cleanStreakDays: 0,
        now: now,
      );
      expect(warnings.single.kind, DoseWarningKind.repeatDose);
      final tolerance = loggingSafetyWarnings(
        draft: [(type: RelapseType.fullLean, at: now)],
        events: const [],
        cleanStreakDays: 12,
        now: now,
      );
      expect(tolerance.single.kind, DoseWarningKind.tolerance);
      expect(tolerance.single.body, contains('12 clean days'));
    });
  });

  group('insight confidence, why and dismissal', () {
    test('confidence thresholds', () {
      expect(confidenceFor(5), InsightConfidence.early);
      expect(confidenceFor(6), InsightConfidence.moderate);
      expect(confidenceFor(11), InsightConfidence.moderate);
      expect(confidenceFor(12), InsightConfidence.strong);
    });

    List<PatternActionInsight> build(
      List<RecoveryEvent> events, {
      Map<String, String> dismissed = const {},
    }) => patternActionInsights(
      cravings: const [],
      sosSessions: const [],
      dailySpend: 0,
      moneySaved: 0,
      relapses: events,
      events: events,
      now: now,
      dismissed: dismissed,
    );

    test('escalation insight carries id, why and confidence', () {
      final events = [
        relapse(daysAgo(10), dose: ml(100)),
        relapse(daysAgo(8), dose: ml(100)),
        relapse(daysAgo(1), dose: ml(150)),
      ];
      final insight = build(
        events,
      ).firstWhere((i) => i.id.startsWith('escalation-'));
      expect(insight.title, 'FULL LEAN DOSE UP 50%');
      expect(insight.evidence, '150 ml VS 100 ml AVG OF 2');
      expect(insight.why, contains('20% or more'));
      expect(insight.confidence, InsightConfidence.early);
      expect(insight.dismissible, isTrue);
    });

    test('dismissal holds until the evidence changes', () {
      final events = [
        relapse(daysAgo(10), dose: ml(100)),
        relapse(daysAgo(8), dose: ml(100)),
        relapse(daysAgo(1), dose: ml(150)),
      ];
      final insight = build(
        events,
      ).firstWhere((i) => i.id.startsWith('escalation-'));
      final dismissed = {insight.id: insight.evidenceKey};
      expect(
        build(events, dismissed: dismissed).any((i) => i.id == insight.id),
        isFalse,
      );
      // A new, higher dose changes the evidence: it comes back.
      final more = [...events, relapse(daysAgo(0, 10), dose: ml(200))];
      expect(
        build(more, dismissed: dismissed).any((i) => i.id == insight.id),
        isTrue,
      );
    });

    test('high need cannot be dismissed', () {
      final events = [craving(daysAgo(0, 10), 7, stress: 5)];
      final insight = build(events).first;
      expect(insight.id, 'high-need');
      expect(insight.dismissible, isFalse);
      expect(
        build(events, dismissed: {'high-need': insight.evidenceKey}).first.id,
        'high-need',
      );
    });
  });

  group('real cost', () {
    test('recorded costs replace the estimate on their day', () {
      final cost = relapseCost(
        relapses: [
          relapse(daysAgo(2, 10), cost: 300),
          relapse(daysAgo(2, 22), cost: 200),
          relapse(daysAgo(5)), // no cost: estimated
        ],
        dailySpend: 400,
        now: now,
      );
      expect(cost.relapseDays, 2);
      expect(cost.realCost, 500);
      expect(cost.costedDays, 1);
      expect(cost.estimatedCost, 400);
      expect(cost.amount, 900);
    });

    test(
      'money series uses real costs and charts them without daily spend',
      () {
        final events = [relapse(daysAgo(2), cost: 350), relapse(daysAgo(1))];
        final withSpend = cumulativeMoneySeries(
          events: events,
          dailySpend: 100,
          now: now,
        );
        expect(withSpend.last.lost, 450);
        expect(withSpend.last.realLost, 350);
        expect(withSpend.last.estimatedLost, 100);

        final noSpend = cumulativeMoneySeries(
          events: events,
          dailySpend: 0,
          now: now,
        );
        expect(noSpend.last.lost, 350);
        expect(noSpend.last.saved, 0);
        expect(
          cumulativeMoneySeries(
            events: [relapse(daysAgo(1))],
            dailySpend: 0,
            now: now,
          ),
          isEmpty,
        );
      },
    );
  });
}
