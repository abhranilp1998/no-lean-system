import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/if_then_plan.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_alert_plan.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/domain/zone_alert_copy.dart';

void main() {
  final at = DateTime(2026, 11, 26, 12);

  IfThenPlan plan(
    String id, {
    String ifText = "I'm bored on the way home",
    String thenText = 'call my brother',
    Set<PlanSurface> surfaces = IfThenPlan.defaultSurfaces,
    String? zoneId,
    String? mood,
  }) => IfThenPlan(
    id: id,
    ifText: ifText,
    thenText: thenText,
    createdAt: at,
    surfaces: surfaces,
    zoneId: zoneId,
    mood: mood,
  );

  group('text', () {
    test('reads as one sentence in the user\'s voice', () {
      expect(
        plan('a').sentence,
        "If I'm bored on the way home, then I will call my brother.",
      );
    });

    test('a leading "If" and "then I will" typed by habit are dropped', () {
      final p = IfThenPlan.create(
        ifText: "If I'm at the shop,",
        thenText: 'Then I will walk home.',
        at: at,
      );
      expect(p.ifText, "I'm at the shop");
      expect(p.thenText, 'walk home');
      expect(p.sentence, "If I'm at the shop, then I will walk home.");
    });

    test('both halves are required and bounded', () {
      expect(
        () => IfThenPlan.create(ifText: ' ', thenText: 'x', at: at),
        throwsFormatException,
      );
      expect(
        () => IfThenPlan.create(ifText: 'x', thenText: '', at: at),
        throwsFormatException,
      );
      expect(
        () => IfThenPlan.create(ifText: 'x' * 121, thenText: 'y', at: at),
        throwsFormatException,
      );
    });
  });

  group('storage', () {
    test('round-trips', () {
      final p = plan(
        'a',
        surfaces: {PlanSurface.zone},
        zoneId: 'z1',
        mood: 'bored',
      );
      final back = IfThenPlan.tryFromJson(p.toJson())!;
      expect(back.sentence, p.sentence);
      expect(back.surfaces, {PlanSurface.zone});
      expect(back.zoneId, 'z1');
      expect(back.mood, 'bored');
    });

    test('missing or odd data reads as no plans, never an error', () {
      expect(IfThenPlan.decodeList(null), isEmpty);
      expect(IfThenPlan.decodeList('nope'), isEmpty);
      expect(
        IfThenPlan.decodeList([
          7,
          {'id': 'x'},
          {
            'id': 'ok',
            'if': 'I feel low',
            'then': 'text Riya',
            'createdAt': '2026-11-01T10:00:00.000',
            'surfaces': ['martian'],
          },
          {
            'id': 'ok',
            'if': 'dup',
            'then': 'dup',
            'createdAt': '2026-11-01T10:00:00.000',
          },
        ]).map((p) => p.id),
        ['ok'],
      );
    });

    test('a plan with no surfaces falls back to showing everywhere', () {
      final p = IfThenPlan.tryFromJson({
        'id': 'a',
        'if': 'x',
        'then': 'y',
        'createdAt': '2026-11-01T10:00:00.000',
      })!;
      expect(p.surfaces, IfThenPlan.defaultSurfaces);
    });
  });

  group('selection', () {
    test('zone plans: that zone first, then any-zone plans, never others', () {
      final plans = [
        plan('any'),
        plan('mine', zoneId: 'z1'),
        plan('other', zoneId: 'z2'),
        plan('no-zone-surface', surfaces: {PlanSurface.window}),
        plan('mood', mood: 'bored'),
      ];
      expect(plansForZone(plans, 'z1').map((p) => p.id), ['mine', 'any']);
      expect(plansForZone(plans, 'zX').map((p) => p.id), ['any']);
    });

    test('window plans skip ones meant for one zone or one mood', () {
      final plans = [
        plan('any'),
        plan('zone', zoneId: 'z1'),
        plan('mood', mood: 'bored'),
        plan('craving-only', surfaces: {PlanSurface.craving}),
      ];
      expect(plansForWindow(plans).map((p) => p.id), ['any']);
    });

    test('craving plans: a mood plan shows only for that mood, first', () {
      final plans = [
        plan('general'),
        plan('bored', mood: 'bored'),
        plan('angry', mood: 'angry'),
      ];
      expect(plansForCraving(plans).map((p) => p.id), ['general']);
      expect(plansForCraving(plans, mood: 'bored').map((p) => p.id), [
        'bored',
        'general',
      ]);
    });
  });

  group('plan moment', () {
    RecoveryEvent c(int hour, int day) => RecoveryEvent.fromJson({
      'id': 'c$day$hour',
      'type': 'craving',
      'timestamp': DateTime(2026, 11, day, hour, 10).toIso8601String(),
      'metadata': {'intensity': 5, 'trigger': 'Habit', 'note': ''},
    });
    const window = RiskWindow(startMinutes: 17 * 60, endMinutes: 21 * 60);

    test('inside the risk window', () {
      expect(
        isPlanMoment(
          now: DateTime(2026, 11, 26, 18),
          window: window,
          events: [],
        ),
        isTrue,
      );
      expect(
        isPlanMoment(
          now: DateTime(2026, 11, 26, 12),
          window: window,
          events: [],
        ),
        isFalse,
      );
    });

    test('around a usual craving peak outside the window', () {
      final events = [c(14, 20), c(14, 21), c(14, 22), c(9, 23), c(15, 24)];
      expect(usualPeakHour(events), 14);
      bool at(int h, int m) => isPlanMoment(
        now: DateTime(2026, 11, 26, h, m),
        window: window,
        events: events,
      );
      expect(at(13, 40), isTrue, reason: '30 min before');
      expect(at(14, 30), isTrue);
      expect(at(15, 30), isFalse, reason: 'past the peak');
      expect(at(12, 0), isFalse);
    });

    test('no peak claimed from a handful of logs', () {
      expect(usualPeakHour([c(14, 20), c(14, 21)]), isNull);
    });
  });

  group('notifications', () {
    final plans = [plan('a', thenText: 'walk to the tea stall')];
    const window = RiskWindow(startMinutes: 17 * 60, endMinutes: 21 * 60);
    final facts = RiskAlertFacts(
      totalCravings: 4,
      cravingsInWindow: 3,
      cleanSince: DateTime(2026, 11, 20),
    );

    test('the warning and the opening alert carry the plan line', () {
      final alerts = buildRiskAlertPlan(
        window: window,
        facts: facts,
        planLine: planNotificationLine(plans.first),
      );
      final pre = alerts.firstWhere((a) => a.kind == RiskAlertKind.preWindow);
      final open = alerts.firstWhere((a) => a.kind == RiskAlertKind.windowOpen);
      for (final a in [pre, open]) {
        expect(a.body, contains('Your plan: If'), reason: '${a.kind}');
        expect(a.body, contains('walk to the tea stall'));
      }
      final follow = alerts.firstWhere((a) => a.kind == RiskAlertKind.followUp);
      expect(follow.body, isNot(contains('Your plan')));
    });

    test('with no plan the alerts are exactly what they were', () {
      final withNull = buildRiskAlertPlan(window: window, facts: facts);
      final withLine = buildRiskAlertPlan(
        window: window,
        facts: facts,
        planLine: 'Your plan: x',
      );
      expect(withNull.map((a) => a.body).join(), isNot(contains('Your plan')));
      expect(withLine.first.body, contains('Your plan: x'));
    });

    test('private notifications never show the plan or any of its words', () {
      const hidden = NotificationPrefs(hideSensitive: true);
      final alerts = buildRiskAlertPlan(
        window: window,
        facts: facts,
        planLine: planNotificationLine(
          plan(
            'a',
            ifText: "I'm at Raju's shop",
            thenText: 'walk to the tea stall',
          ),
        ),
      );
      for (final a in alerts) {
        final text = hidden.textFor(a.title, a.body);
        expect(
          '${text.title} ${text.body}'.toLowerCase(),
          isNot(contains('raju')),
        );
        expect(text.body.toLowerCase(), isNot(contains('tea stall')));
        expect(text.body.toLowerCase(), isNot(contains('plan')));
      }
    });

    test('a zone alert names the plan; private mode swallows it', () {
      final zone = DangerZone(
        id: 'z1',
        name: 'Bus stand',
        latitude: 12.9,
        longitude: 77.5,
        radiusMeters: 200,
        createdAt: DateTime(2026, 11, 1),
      );
      final copy = buildZoneAlertCopy(
        zone: zone,
        now: at,
        plans: [plan('mine', zoneId: 'z1', thenText: 'cross the road')],
      );
      expect(copy.body, contains('Your plan: If'));
      expect(copy.body, contains('cross the road'));
      expect(copy.screenText, isNot(contains('Your plan')));
      expect(copy.plans.single.id, 'mine');
      final hidden = const NotificationPrefs(
        hideSensitive: true,
      ).textFor(copy.title, copy.body);
      expect(hidden.body.toLowerCase(), isNot(contains('cross the road')));
      expect(hidden.title.toLowerCase(), isNot(contains('bus stand')));

      final none = buildZoneAlertCopy(zone: zone, now: at);
      expect(none.body, isNot(contains('Your plan')));
      expect(none.screenBody, isNull);
    });
  });
}
