import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/craving_peak.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';

void main() {
  final now = DateTime(2026, 11, 26, 12);

  RecoveryEvent craving(DateTime at) => RecoveryEvent.create(
    type: RecoveryEventType.craving,
    timestamp: at,
    metadata: const {'intensity': 6, 'trigger': 'evening'},
  );
  RecoveryEvent slip(DateTime at) => RecoveryEvent.create(
    type: RecoveryEventType.relapse,
    timestamp: at,
    metadata: {'recordedAt': now.toIso8601String()},
  );

  /// Five 19:00 signals on five different days, plus a couple of decoys.
  List<RecoveryEvent> eveningPeak({int hour = 19, int days = 5}) => [
    for (var i = 0; i < days; i++)
      craving(DateTime(2026, 11, 20 + i, hour, 10 + i)),
    craving(DateTime(2026, 11, 21, 9, 0)),
    slip(DateTime(2026, 11, 22, 11, 30)),
  ];

  const defaultWindow = RiskWindow(startMinutes: 17 * 60, endMinutes: 21 * 60);
  // A window that does not swallow a 7 PM peak.
  const morningWindow = RiskWindow(startMinutes: 8 * 60, endMinutes: 11 * 60);

  test('needs 5 signals across 3 days before it activates', () {
    expect(
      buildCravingPeakPlan(
        events: [
          for (var i = 0; i < 4; i++) craving(DateTime(2026, 11, 20 + i, 19)),
        ],
        riskWindow: morningWindow,
        now: now,
      ),
      isNull,
    );
    // 5 signals but only 2 days.
    expect(
      buildCravingPeakPlan(
        events: [
          for (var i = 0; i < 3; i++) craving(DateTime(2026, 11, 20, 19, i)),
          craving(DateTime(2026, 11, 21, 19)),
          slip(DateTime(2026, 11, 21, 19, 30)),
        ],
        riskWindow: morningWindow,
        now: now,
      ),
      isNull,
    );
  });

  test('finds the peak hour from occurredAt, not recordedAt', () {
    final plan = buildCravingPeakPlan(
      events: eveningPeak(),
      riskWindow: morningWindow,
      now: now,
    );
    expect(plan, isNotNull);
    expect(plan!.peakHour, 19);
    expect(plan.headsUpMinutes, 18 * 60 + 30);
    expect(plan.count, 5);
    expect(plan.isDaily, isTrue);
    // The slip was written down at noon (recordedAt) but occurred at 11:30.
    expect(occurredAtOf(eveningPeak().last).hour, 11);
  });

  test(
    'skips when the peak sits inside or at the start of the risk window',
    () {
      expect(
        buildCravingPeakPlan(
          events: eveningPeak(),
          riskWindow: defaultWindow,
          now: now,
        ),
        isNull,
      );
      // Peak at 17:00, window starts 17:00 — would duplicate the open alert.
      expect(
        buildCravingPeakPlan(
          events: eveningPeak(hour: 17),
          riskWindow: defaultWindow,
          now: now,
        ),
        isNull,
      );
      // Heads-up at 16:30 would land just before a 17:00 window; peak itself
      // at 17:00 is at the start, so skip.
      expect(
        buildCravingPeakPlan(
          events: eveningPeak(hour: 17),
          riskWindow: const RiskWindow(
            startMinutes: 17 * 60,
            endMinutes: 18 * 60,
          ),
          now: now,
        ),
        isNull,
      );
    },
  );

  test('still fires when the peak is well outside the risk window', () {
    final plan = buildCravingPeakPlan(
      events: eveningPeak(),
      riskWindow: morningWindow,
      now: now,
    );
    expect(plan?.peakHour, 19);
    expect(plan?.headsUpMinutes, 18 * 60 + 30);
  });

  test('skips when the heads-up would fire inside the window', () {
    // Peak at 22:00, heads-up 21:30, window 17:00–21:59 (ends at 21:59 incl).
    expect(
      buildCravingPeakPlan(
        events: eveningPeak(hour: 22),
        riskWindow: const RiskWindow(
          startMinutes: 17 * 60,
          endMinutes: 21 * 60 + 59,
        ),
        now: now,
      ),
      isNull,
    );
  });

  test('a tied top hour is not a clear peak', () {
    final events = [
      for (var i = 0; i < 3; i++) craving(DateTime(2026, 11, 20 + i, 14)),
      for (var i = 0; i < 3; i++) slip(DateTime(2026, 11, 20 + i, 20)),
    ];
    expect(
      buildCravingPeakPlan(events: events, riskWindow: morningWindow, now: now),
      isNull,
    );
  });

  test('weekday-concentrated peaks only fire on those days', () {
    // Five Fridays at 19:00, plus one Thursday decoy at 19:00.
    final events = [
      for (final day in [6, 13, 20, 27]) // Nov 2026 Fridays: 6,13,20,27
        craving(DateTime(2026, 11, day, 19, 15)),
      craving(DateTime(2026, 10, 30, 19, 0)), // Friday
      craving(DateTime(2026, 11, 19, 19, 0)), // Thursday decoy
      craving(DateTime(2026, 11, 18, 10, 0)),
    ];
    final plan = buildCravingPeakPlan(
      events: events,
      riskWindow: morningWindow,
      now: DateTime(2026, 11, 28, 12),
    );
    expect(plan, isNotNull);
    expect(plan!.peakHour, 19);
    expect(plan.weekdays, [DateTime.friday]);
    expect(plan.copy.title, 'USUAL PEAK Fridays AROUND 7 PM');
    expect(
      plan.copy.body,
      'Your Fridays usually get hard around 7 PM. '
      'Plan something now: call your person, walk, or eat.',
    );
  });

  test('copy names the hour and one concrete plan', () {
    final text = cravingPeakCopy(peakHour: 19);
    expect(text.title, 'USUAL PEAK AROUND 7 PM');
    expect(
      text.body,
      'Your cravings usually hit around 7 PM. '
      'Plan something now: call your person, walk, or eat.',
    );
    expect(formatPeakHour(0), '12 AM');
    expect(formatPeakHour(12), '12 PM');
    expect(formatPeakHour(7), '7 AM');
  });

  test('private wording layer strips every sensitive word', () {
    const hidden = NotificationPrefs(hideSensitive: true);
    final plan = buildCravingPeakPlan(
      events: eveningPeak(),
      riskWindow: morningWindow,
      now: now,
    )!;
    final text = hidden.textFor(plan.copy.title, plan.copy.body);
    expect(text.title, neutralNotificationText.title);
    expect(text.body, neutralNotificationText.body);
    final visible =
        '${text.title} ${text.body} ${hidden.label('OPEN SOS', 'OPEN')}';
    for (final word in ['craving', 'peak', 'lean', 'slip', 'relapse', 'sos']) {
      expect(visible.toLowerCase(), isNot(contains(word)), reason: word);
    }
  });

  test('midnight peak wraps the heads-up to 11:30 PM', () {
    final events = [
      for (var i = 0; i < 5; i++) craving(DateTime(2026, 11, 20 + i, 0, 5)),
    ];
    final plan = buildCravingPeakPlan(
      events: events,
      riskWindow: morningWindow,
      now: now,
    );
    expect(plan?.peakHour, 0);
    expect(plan?.headsUpMinutes, 23 * 60 + 30);
    expect(plan?.copy.title, 'USUAL PEAK AROUND 12 AM');
  });

  test('channel constants are ready for the PR #33 catalogue', () {
    expect(cravingPeakChannel.id, 'craving_peak_v1');
    expect(cravingPeakChannel.privateName, 'Daily check-in');
    expect(cravingPeakChannel.publicName.toLowerCase(), contains('lean'));
    expect(
      cravingPeakChannel.privateName.toLowerCase(),
      isNot(contains('lean')),
    );
    expect(
      cravingPeakChannel.privateDescription.toLowerCase(),
      isNot(contains('craving')),
    );
  });

  test('settings subtitle covers off, waiting, overlap and a live plan', () {
    expect(
      cravingPeakSettingSubtitle(
        enabled: false,
        insight: const CravingPeakInsight.skip(CravingPeakSkip.needsData),
      ),
      'Off',
    );
    expect(
      cravingPeakSettingSubtitle(
        enabled: true,
        insight: const CravingPeakInsight.skip(CravingPeakSkip.needsData),
      ),
      'On // needs 5 cravings or slips across 3 days to start',
    );
    expect(
      cravingPeakSettingSubtitle(
        enabled: true,
        insight: const CravingPeakInsight.skip(
          CravingPeakSkip.overlapsRiskWindow,
        ),
      ),
      'On // skipped because the usual peak is already inside the risk window',
    );
    final insight = analyzeCravingPeak(
      events: eveningPeak(),
      riskWindow: morningWindow,
      now: now,
    );
    expect(
      cravingPeakSettingSubtitle(enabled: true, insight: insight),
      contains('30 min before your usual 7 PM peak'),
    );
  });
}
