import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_alert_plan.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';

void main() {
  const window = RiskWindow.defaultWindow(); // 17:00–21:00
  final cleanSince = DateTime(2026, 10, 3, 9);

  RecoveryEvent craving(DateTime at, String trigger) => RecoveryEvent.create(
    type: RecoveryEventType.craving,
    timestamp: at,
    metadata: {'intensity': 7, 'trigger': trigger},
  );

  test('facts count only logged cravings and their window share', () {
    final events = [
      craving(DateTime(2026, 10, 1, 18, 10), 'Payday'),
      craving(DateTime(2026, 10, 2, 19, 40), 'Payday'),
      craving(DateTime(2026, 10, 3, 18, 5), 'Stress'),
      craving(DateTime(2026, 10, 4, 9, 0), 'Stress'),
      RecoveryEvent.create(type: RecoveryEventType.pledge),
    ];
    final facts = computeRiskAlertFacts(
      events: events,
      window: window,
      cleanSince: cleanSince,
    );
    expect(facts.totalCravings, 4);
    expect(facts.cravingsInWindow, 3);
    expect(facts.windowSharePercent, 75);
    expect(facts.topTrigger, 'Payday');
    expect(facts.topTriggerCount, 2);
    expect(facts.peakHour, 18);
  });

  test('plan has a 15-minute warning, an opening alert and follow-ups', () {
    final plan = buildRiskAlertPlan(
      window: window,
      facts: RiskAlertFacts(
        totalCravings: 4,
        cravingsInWindow: 3,
        cleanSince: cleanSince,
        topTrigger: 'Payday',
        topTriggerCount: 2,
        peakHour: 18,
      ),
      userMessages: const ['Call Riya before 18:00.'],
    );

    expect(plan.map((a) => a.kind), [
      RiskAlertKind.preWindow,
      RiskAlertKind.windowOpen,
      RiskAlertKind.followUp,
      RiskAlertKind.followUp,
      RiskAlertKind.followUp,
    ]);
    expect(plan.map((a) => a.minuteOfDay), [
      16 * 60 + 45,
      17 * 60,
      18 * 60,
      19 * 60,
      20 * 60,
    ]);
    expect(plan.map((a) => a.id), [510, 500, 501, 502, 503]);

    final pre = plan.first;
    expect(pre.title, 'RISK WINDOW IN 15 MIN // 17:00—21:00');
    expect(pre.body, contains('75% of your 4 logged cravings hit inside'));
    expect(pre.body, contains('Top trigger in this window: PAYDAY (2 logs).'));
    expect(pre.body, contains('Clean since 3 Oct.'));
    expect(plan[1].body, contains('Call Riya before 18:00.'));
    expect(plan[2].title, 'FOLLOW-UP // WINDOW ENDS 21:00');
    expect(plan[2].body, contains('Peak hour in your logs: 18:00.'));
  });

  test('without data the copy asks for logs instead of inventing numbers', () {
    final plan = buildRiskAlertPlan(
      window: window,
      facts: RiskAlertFacts(
        totalCravings: 0,
        cravingsInWindow: 0,
        cleanSince: cleanSince,
      ),
    );
    final copy = plan.map((a) => a.body).join(' ');
    expect(copy, contains('No craving data for this window yet.'));
    expect(copy, isNot(contains('%')));
    expect(plan.last.body, contains('Still inside the window.'));
  });

  test('small samples report counts, not percentages', () {
    final plan = buildRiskAlertPlan(
      window: window,
      facts: RiskAlertFacts(
        totalCravings: 2,
        cravingsInWindow: 1,
        cleanSince: cleanSince,
      ),
    );
    expect(plan.first.body, contains('1 of your 2 logged cravings hit inside'));
  });

  test('a midnight-spanning window wraps the warning time', () {
    final plan = buildRiskAlertPlan(
      window: const RiskWindow(startMinutes: 5, endMinutes: 120),
      facts: RiskAlertFacts(
        totalCravings: 0,
        cravingsInWindow: 0,
        cleanSince: cleanSince,
      ),
    );
    expect(plan.first.minuteOfDay, 23 * 60 + 50);
  });

  test('copy stays firm without punitive language', () {
    final plan = buildRiskAlertPlan(
      window: window,
      facts: RiskAlertFacts(
        totalCravings: 5,
        cravingsInWindow: 4,
        cleanSince: cleanSince,
        topTrigger: 'Stress',
        topTriggerCount: 3,
        peakHour: 19,
      ),
    );
    final copy = plan
        .map((a) => '${a.title} ${a.body}')
        .join(' ')
        .toLowerCase();
    for (final word in ['failure', 'weak', 'shame', 'pathetic', 'loser']) {
      expect(copy, isNot(contains(word)));
    }
  });
}
