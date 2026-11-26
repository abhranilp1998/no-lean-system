import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/risk_alert_plan.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/domain/slip_review.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';

RecoveryEvent slip(String id, DateTime at, [Map<String, dynamic>? meta]) =>
    RecoveryEvent.fromJson({
      'id': id,
      'type': 'relapse',
      'timestamp': at.toIso8601String(),
      'metadata': meta ?? <String, dynamic>{},
    });

void main() {
  final now = DateTime(2026, 11, 26, 22);

  group('applySlipReview', () {
    test('adds only its own keys, unions tags, removes nothing', () {
      final meta = applySlipReview(
        {
          'note': 'hard night',
          'contextTags': ['Stress'],
          'futureKey': 7,
          'recordedAt': '2026-11-26T20:00:00.000',
        },
        const SlipReview(
          place: " Friend's place ",
          withWho: 'friends',
          triggers: ['Stress', 'Payday'],
        ),
        now: now,
      );
      expect(meta['place'], "Friend's place");
      expect(meta['withWho'], 'friends');
      expect(meta['contextTags'], ['Stress', 'Payday']);
      expect(meta['note'], 'hard night');
      expect(meta['futureKey'], 7);
      expect(meta['recordedAt'], '2026-11-26T20:00:00.000');
      expect(meta['reviewedAt'], isNotNull);
    });

    test('a zone link keeps its id; a typed place clears a stale link', () {
      final linked = applySlipReview(
        {},
        const SlipReview(place: 'Pharmacy', zoneId: 'z1'),
        now: now,
      );
      expect(linked['zoneId'], 'z1');
      final typed = applySlipReview(
        linked,
        const SlipReview(place: 'Home'),
        now: now,
      );
      expect(typed.containsKey('zoneId'), isFalse);
    });

    test('empty review is empty; unknown "with" is ignored', () {
      expect(const SlipReview().isEmpty, isTrue);
      expect(const SlipReview(withWho: 'martians').isEmpty, isTrue);
      expect(const SlipReview(triggers: ['Stress']).isEmpty, isFalse);
    });
  });

  test('normalize drops bad optional values and never throws', () {
    final m = normalizeSlipReviewMetadata({
      'place': 42,
      'zoneId': '',
      'withWho': ['x'],
      'reviewedAt': 5,
      'keep': 'me',
    });
    expect(m, {'keep': 'me'});
    final long = normalizeSlipReviewMetadata({'place': 'x' * 500});
    expect((long['place'] as String).length, slipPlaceMaxLength);
  });

  group('zone suggestions', () {
    final zones = [
      DangerZone(
        id: 'z',
        name: 'Pharmacy',
        latitude: 1,
        longitude: 1,
        radiusMeters: 150,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
    test('2+ reviewed slips at an un-fenced place suggest a zone', () {
      final events = [
        slip('1', now, {'place': "Friend's place"}),
        slip('2', now, {'place': "friend's place"}),
        slip('3', now, {'place': 'Home'}),
        slip('4', now, {'place': 'Home'}),
        slip('5', now, {'place': 'Outside'}),
        slip('6', now, {'place': 'Outside'}),
        slip('7', now, {'place': 'Pharmacy'}),
        slip('8', now, {'place': 'Pharmacy'}),
        slip('9', now, {'place': 'Shop / bar', 'zoneId': 'z'}),
        slip('10', now, {'place': 'Shop / bar', 'zoneId': 'z'}),
      ];
      final s = zoneSuggestions(events, zones);
      expect(s.map((e) => e.place), ["Friend's place"]);
      expect(s.single.count, 2);
    });

    test('one slip is not a pattern', () {
      expect(
        zoneSuggestions([
          slip('1', now, {'place': 'Work'}),
        ], const []),
        isEmpty,
      );
    });
  });

  group('timing', () {
    const window = RiskWindow.defaultWindow(); // 17:00-21:00

    test('slips just before the window push the warning earlier', () {
      final events = [
        slip('1', DateTime(2026, 11, 20, 15, 40)),
        slip('2', DateTime(2026, 11, 22, 16, 10)),
        slip('3', DateTime(2026, 11, 23, 18)), // inside window
      ];
      final p = computeSlipPattern(events, window);
      expect(p.minutesBeforeWindow, 90);
      expect(adaptiveLeadMinutes(p), 90);
    });

    test('one early slip, or none, keeps the default 15 min', () {
      final one = computeSlipPattern([
        slip('1', DateTime(2026, 11, 20, 15, 40)),
      ], window);
      expect(adaptiveLeadMinutes(one), 15);
      expect(adaptiveLeadMinutes(computeSlipPattern(const [], window)), 15);
    });

    test('never shorter than the base and capped at 3 hours', () {
      expect(
        adaptiveLeadMinutes(
          const SlipPattern(total: 3, minutesBeforeWindow: 5),
        ),
        15,
      );
      expect(
        adaptiveLeadMinutes(
          const SlipPattern(total: 3, minutesBeforeWindow: 400),
        ),
        180,
      );
    });

    test('reviewed place and company appear in the pre-window alert', () {
      final events = [
        slip('1', DateTime(2026, 11, 20, 18), {
          'place': "Friend's place",
          'withWho': 'friends',
        }),
        slip('2', DateTime(2026, 11, 21, 18), {
          'place': "Friend's place",
          'withWho': 'friends',
        }),
      ];
      final facts = computeRiskAlertFacts(
        events: events,
        window: window,
        cleanSince: DateTime(2026, 11, 22),
      );
      expect(facts.slipPlace, "Friend's place");
      final plan = buildRiskAlertPlan(window: window, facts: facts);
      final pre = plan.firstWhere((a) => a.kind == RiskAlertKind.preWindow);
      expect(
        pre.body,
        contains(
          "Your reviewed slips keep happening at Friend's place (2x), often friends.",
        ),
      );
    });

    test('a single reviewed slip adds no place line', () {
      final facts = computeRiskAlertFacts(
        events: [
          slip('1', DateTime(2026, 11, 20, 18), {'place': 'Work'}),
        ],
        window: window,
        cleanSince: DateTime(2026, 11, 22),
      );
      expect(facts.slipPlace, isNull);
    });
  });

  group('slipReviewFor', () {
    test('one entry, or one episode, gets a request; a catch-up does not', () {
      expect(slipReviewFor([slip('1', now)])?.eventIds, {'1'});
      expect(
        slipReviewFor([
          slip('1', now),
          slip('2', now.subtract(const Duration(hours: 5))),
        ])?.eventIds,
        {'1', '2'},
      );
      expect(
        slipReviewFor([
          slip('1', now),
          slip('2', now.subtract(const Duration(days: 3))),
        ]),
        isNull,
      );
      expect(slipReviewFor(const []), isNull);
    });
  });
}
