import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/progress/domain/recovery_insights.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/domain/sos_session.dart';

void main() {
  test('chronological series sorts newest-first storage into time order', () {
    final later = _craving(DateTime(2026, 8, 7, 20), intensity: 8);
    final earlier = _craving(DateTime(2026, 8, 7, 18), intensity: 5);

    final series = chronologicalCravingSeries([later, earlier]);

    expect(series.map((point) => point.timestamp), [
      earlier.createdAt,
      later.createdAt,
    ]);
  });

  test('trigger and time-of-day breakdowns expose repeat patterns', () {
    final entries = [
      _craving(DateTime(2026, 8, 7, 18), trigger: 'After Work', intensity: 8),
      _craving(DateTime(2026, 8, 6, 19), trigger: 'After Work', intensity: 6),
      _craving(DateTime(2026, 8, 6, 9), trigger: 'Stress', intensity: 4),
    ];

    final triggers = triggerBreakdown(entries);
    final timeBands = timeOfDayBreakdown(entries);

    expect(triggers.first.label, 'After Work');
    expect(triggers.first.count, 2);
    expect(triggers.first.averageIntensity, 7);
    expect(
      timeBands.singleWhere((item) => item.label.startsWith('EVENING')).count,
      2,
    );
  });

  test('SOS summary tracks completions, abandons, and average duration', () {
    final started = DateTime(2026, 8, 7, 18);
    final sessions = [
      SosSession(
        startedAt: started,
        completedAt: started.add(const Duration(seconds: 60)),
      ),
      SosSession(startedAt: started.add(const Duration(hours: 1))),
      SosSession(
        startedAt: started.add(const Duration(hours: 2)),
        completedAt: started.add(const Duration(hours: 2, seconds: 30)),
      ),
    ];

    final summary = sosCompletionSummary(sessions);

    expect(summary.started, 3);
    expect(summary.completed, 2);
    expect(summary.completionRate, closeTo(2 / 3, .001));
    expect(summary.averageDuration, const Duration(seconds: 45));
  });

  test('action engine prioritizes repeated high-intensity cravings', () {
    final day = DateTime(2026, 8, 7);
    final insights = patternActionInsights(
      cravings: [
        _craving(day.add(const Duration(hours: 18)), intensity: 9),
        _craving(day.add(const Duration(hours: 20)), intensity: 8),
      ],
      sosSessions: const [],
      dailySpend: 0,
      moneySaved: 0,
    );

    expect(insights.first.title, 'REPEAT SPIKE DETECTED');
    expect(insights.first.action, PatternActionKind.openSos);
    expect(insights.first.evidence, contains('2 HIGH-INTENSITY LOGS'));
  });

  test('action engine avoids confident patterns without repeat evidence', () {
    final insights = patternActionInsights(
      cravings: [_craving(DateTime(2026, 8, 7, 18), intensity: 6)],
      sosSessions: const [],
      dailySpend: 0,
      moneySaved: 0,
    );

    expect(insights, hasLength(1));
    expect(insights.single.title, 'BUILD THE SIGNAL BASELINE');
    expect(insights.single.action, PatternActionKind.logCraving);
  });
  group('risk-signal engine', () {
    const window = RiskWindow(startMinutes: 17 * 60, endMinutes: 21 * 60);
    final now = DateTime(2026, 8, 20, 12);

    test('relapse context tags feed the trigger breakdown', () {
      final signals = riskSignals(
        cravings: [
          _craving(DateTime(2026, 8, 7, 18), trigger: 'Friends', intensity: 8),
          _craving(DateTime(2026, 8, 8, 9), trigger: 'Stress', intensity: 4),
        ],
        relapses: [
          _relapse(DateTime(2026, 8, 9, 22), tags: ['Friends', 'Party']),
          _relapse(DateTime(2026, 8, 10, 23)), // untagged: time only
        ],
      );
      final triggers = signalTriggerBreakdown(signals);
      final friends = triggers.first;
      expect(friends.label, 'Friends');
      expect(friends.count, 2);
      expect(friends.relapseCount, 1);
      expect(friends.averageIntensity, 8); // cravings only
      expect(friends.ratio, closeTo(2 / 3, .001)); // 3 tagged signals

      final bands = signalTimeBreakdown(signals);
      final evening = bands.singleWhere((b) => b.label.startsWith('EVENING'));
      expect(evening.count, 3);
      expect(evening.relapseCount, 2);
    });

    test('patterns stay hidden below the minimum data threshold', () {
      final insights = patternActionInsights(
        cravings: [
          for (var i = 0; i < 4; i++)
            _craving(DateTime(2026, 8, 1 + i, 18), trigger: 'Friends'),
        ],
        sosSessions: const [],
        dailySpend: 0,
        moneySaved: 0,
        riskWindow: window,
        now: now,
      );
      expect(insights.map((i) => i.title), ['BUILD THE SIGNAL BASELINE']);
      expect(insights.single.evidence, contains('4/5 SIGNALS'));
    });

    test('a confirmed window cites cravings and relapses inside it', () {
      final insights = patternActionInsights(
        cravings: [
          for (var i = 0; i < 3; i++)
            _craving(DateTime(2026, 8, 1 + i, 18), trigger: 'Friends'),
          _craving(DateTime(2026, 8, 5, 9), trigger: 'Stress'),
        ],
        relapses: [
          _relapse(DateTime(2026, 8, 6, 19, 30), tags: ['Friends']),
        ],
        sosSessions: const [],
        dailySpend: 0,
        moneySaved: 0,
        riskWindow: window,
        now: now,
      );
      final trigger = insights.singleWhere(
        (i) => i.title == 'FRIENDS OWNS THE LOOP',
      );
      expect(trigger.body, contains('80% of your 5 logged signals'));
      expect(trigger.body, contains('1 relapse came out of it'));
      final confirmed = insights.singleWhere(
        (i) => i.title.contains('WINDOW IS CONFIRMED'),
      );
      expect(confirmed.evidence, '4 OF 5 SIGNALS // 80% IN WINDOW');
      expect(confirmed.body, contains('1 relapse landed inside it'));
    });

    test('flags a misplaced window when the data sits elsewhere', () {
      final insights = patternActionInsights(
        cravings: [
          for (var i = 0; i < 4; i++)
            _craving(DateTime(2026, 8, 1 + i, 13), trigger: 'Trigger $i'),
        ],
        relapses: [_relapse(DateTime(2026, 8, 6, 14))],
        sosSessions: const [],
        dailySpend: 0,
        moneySaved: 0,
        riskWindow: window,
        now: now,
      );
      final misplaced = insights.singleWhere(
        (i) => i.title == 'YOUR RISK WINDOW IS MISPLACED',
      );
      expect(misplaced.body, contains('Only 0% of your 5 signals'));
      expect(misplaced.body, contains('100% hit AFTERNOON / 12-16'));
      expect(misplaced.action, PatternActionKind.editRiskWindow);
      expect(insights.any((i) => i.title.contains('OWNS THE LOOP')), isFalse);
    });

    test('money lost counts distinct relapse days in the last 30 days', () {
      final cost = relapseCost(
        relapses: [
          _relapse(DateTime(2026, 8, 18, 20)),
          _relapse(DateTime(2026, 8, 18, 23)), // same day
          _relapse(DateTime(2026, 8, 2, 20)),
          _relapse(DateTime(2026, 7, 1, 20)), // outside 30 days
        ],
        dailySpend: 25,
        now: now,
      );
      expect(cost.relapseDays, 2);
      expect(cost.amount, 50);

      final insights = patternActionInsights(
        cravings: const [],
        relapses: [_relapse(DateTime(2026, 8, 18, 20))],
        sosSessions: const [],
        dailySpend: 25,
        moneySaved: 0,
        now: now,
      );
      final money = insights.singleWhere(
        (i) => i.title == 'RELAPSES COST 25 THIS MONTH',
      );
      expect(money.evidence, contains('ESTIMATE FROM DAILY SPEND'));
      expect(money.action, PatternActionKind.pledge);
    });

    test('insight copy stays firm without shaming language', () {
      final insights = patternActionInsights(
        cravings: [
          for (var i = 0; i < 6; i++)
            _craving(DateTime(2026, 8, 1 + i, 18), trigger: 'Friends'),
        ],
        relapses: [
          _relapse(DateTime(2026, 8, 18, 20), tags: ['Friends']),
        ],
        sosSessions: const [],
        dailySpend: 10,
        moneySaved: 0,
        riskWindow: window,
        now: now,
      );
      for (final insight in insights) {
        final text = '${insight.title} ${insight.body}'.toLowerCase();
        for (final word in ['weak', 'shame', 'pathetic', 'failure', 'loser']) {
          expect(text, isNot(contains(word)));
        }
      }
    });
  });
}

RecoveryEvent _relapse(DateTime at, {List<String>? tags}) =>
    RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      timestamp: at,
      metadata: {'contextTags': ?tags},
    );

CravingEntry _craving(
  DateTime createdAt, {
  String trigger = 'Other',
  int intensity = 5,
}) => CravingEntry(
  intensity: intensity,
  trigger: trigger,
  note: '',
  createdAt: createdAt,
);
