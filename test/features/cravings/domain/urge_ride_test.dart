import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/cravings/domain/urge_ride.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/slip_tone.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

RecoveryEvent craving({
  required DateTime at,
  int intensity = 6,
  bool ride = true,
}) => RecoveryEvent.create(
  type: RecoveryEventType.craving,
  timestamp: at,
  metadata: {
    'intensity': intensity,
    'trigger': ride ? 'Ride it out' : 'Other',
    'note': ride ? 'Ten-minute ride' : '',
    if (ride) 'urgeRide': true,
  },
);

RecoveryEvent checkFor(
  RecoveryEvent craving, {
  required DateTime at,
  required UrgeRideOutcome outcome,
  required UrgeRideActivity activity,
  bool haptic = false,
}) {
  final ride = UrgeRide(
    id: 'x',
    startedAt: craving.timestamp,
    endedAt: at,
    outcome: outcome,
    activity: activity,
    hapticPacing: haptic,
    intensityBefore: (craving.metadata['intensity'] as int?) ?? 6,
  );
  return RecoveryEvent.create(
    type: RecoveryEventType.cravingCheck,
    timestamp: at,
    metadata: ride.checkMetadata(craving.id),
  );
}

void main() {
  final t = DateTime(2026, 11, 26, 21);

  group('breathing pace', () {
    test('alternates every four seconds', () {
      expect(breathPhaseAt(Duration.zero), BreathPhase.inhale);
      expect(breathPhaseAt(const Duration(seconds: 3)), BreathPhase.inhale);
      expect(breathPhaseAt(const Duration(seconds: 4)), BreathPhase.exhale);
      expect(breathPhaseAt(const Duration(seconds: 8)), BreathPhase.inhale);
      expect(breathPhaseLabel(BreathPhase.inhale), 'Breathe in');
      expect(breathPhaseLabel(BreathPhase.exhale), 'Breathe out');
    });
  });

  group('from events', () {
    test('an older recheck without urgeRide is not a ride', () {
      final c = craving(at: t, ride: false);
      final recheck = RecoveryEvent.create(
        type: RecoveryEventType.cravingCheck,
        timestamp: t.add(const Duration(minutes: 15)),
        metadata: {
          'cravingId': c.id,
          'intensity': 0,
          'outcome': 'gone',
          'originalIntensity': 6,
        },
      );
      expect(UrgeRide.fromEvents([c, recheck]), isEmpty);
      expect(WhatWorkedStats.fromEvents([c, recheck]).total, 0);
    });

    test('a finished ride round-trips, including optional keys', () {
      final c = craving(at: t);
      final k = checkFor(
        c,
        at: t.add(const Duration(minutes: 10)),
        outcome: UrgeRideOutcome.yes,
        activity: UrgeRideActivity.walk,
        haptic: true,
      );
      final ride = UrgeRide.fromEvents([c, k]).single;
      expect(ride.outcome, UrgeRideOutcome.yes);
      expect(ride.activity, UrgeRideActivity.walk);
      expect(ride.hapticPacing, isTrue);
      expect(ride.plannedMinutes, 10);
      expect(ride.intensityBefore, 6);
    });

    test('an older check with urgeRide but no new keys still decodes', () {
      final c = craving(at: t);
      final k = RecoveryEvent.create(
        type: RecoveryEventType.cravingCheck,
        timestamp: t.add(const Duration(minutes: 8)),
        metadata: {
          'cravingId': c.id,
          'intensity': 2,
          'outcome': 'eased',
          'originalIntensity': 6,
          'urgeRide': true,
        },
      );
      final ride = UrgeRide.fromEvents([c, k]).single;
      expect(ride.outcome, UrgeRideOutcome.aBit);
      expect(ride.activity, UrgeRideActivity.other);
      expect(ride.hapticPacing, isFalse);
    });
  });

  group('what works', () {
    List<RecoveryEvent> rides(List<(UrgeRideActivity, UrgeRideOutcome)> items) {
      final events = <RecoveryEvent>[];
      for (var i = 0; i < items.length; i++) {
        final at = t.add(Duration(hours: i));
        final c = craving(at: at);
        events
          ..add(c)
          ..add(
            checkFor(
              c,
              at: at.add(const Duration(minutes: 10)),
              outcome: items[i].$2,
              activity: items[i].$1,
            ),
          );
      }
      return events;
    }

    test('needs the minimum sample before an activity is ranked', () {
      final events = rides([
        (UrgeRideActivity.walk, UrgeRideOutcome.yes),
        (UrgeRideActivity.walk, UrgeRideOutcome.yes),
        (UrgeRideActivity.music, UrgeRideOutcome.yes),
        (UrgeRideActivity.music, UrgeRideOutcome.yes),
        (UrgeRideActivity.music, UrgeRideOutcome.yes),
        (UrgeRideActivity.music, UrgeRideOutcome.no),
      ]);
      final stats = WhatWorkedStats.fromEvents(events);
      expect(stats.total, 6);
      expect(stats.passed, 5);
      expect(stats.ranked.map((r) => r.activity), [UrgeRideActivity.music]);
      expect(stats.ranked.single.passed, 3);
      expect(stats.ranked.single.total, 4);
      expect(stats.waiting.map((r) => r.activity), [UrgeRideActivity.walk]);
      expect(stats.top!.activity, UrgeRideActivity.music);
    });

    test('a bit counts half in the pass rate, so a clear yes ranks higher', () {
      final events = rides([
        for (var i = 0; i < 3; i++)
          (UrgeRideActivity.shower, UrgeRideOutcome.aBit),
        for (var i = 0; i < 3; i++)
          (UrgeRideActivity.walk, UrgeRideOutcome.yes),
      ]);
      final stats = WhatWorkedStats.fromEvents(events);
      expect(stats.ranked.first.activity, UrgeRideActivity.walk);
      expect(stats.ranked.last.activity, UrgeRideActivity.shower);
      expect(stats.ranked.first.passRate, 1);
      expect(stats.ranked.last.passRate, 0.5);
    });

    test('copy is warm, uses their numbers, and never names a helpline', () {
      final empty = WhatWorkedStats(const []);
      final some = WhatWorkedStats.fromEvents(
        rides([
          for (var i = 0; i < 3; i++)
            (UrgeRideActivity.walk, UrgeRideOutcome.yes),
          (UrgeRideActivity.walk, UrgeRideOutcome.no),
        ]),
      );
      expect(empty.copyIsWarm, isTrue);
      expect(some.copyIsWarm, isTrue);
      expect(some.homeHeadline, contains('3 of 4'));
      expect(some.homeBody.toLowerCase(), contains('walk'));
      final all = [
        empty.homeHeadline,
        empty.homeBody,
        some.homeHeadline,
        some.homeBody,
        'Ten minutes. You do not have to win it. You only have to stay with it.',
        'Logged. That is data you can use next time.',
      ].join(' ').toLowerCase();
      for (final word in [
        'failed',
        'failure',
        'helpline',
        'hotline',
        '112',
        '911',
        'ruined',
        'weak',
      ]) {
        expect(all, isNot(contains(word)), reason: word);
      }
      expect(isWarmCopy(some.homeHeadline), isTrue);
    });
  });

  group('backups stay compatible', () {
    test('every existing backup format still validates', () {
      final pledge = {
        'id': 'p-1',
        'type': 'pledge',
        'timestamp': DateTime(2026, 1, 1, 9).toIso8601String(),
        'metadata': <String, dynamic>{},
      };
      for (
        var format = 1;
        format <= BackupService.currentBackupVersion;
        format++
      ) {
        final preview = BackupService().validateBackupJson(
          jsonEncode({
            'version': format,
            'events': [pledge],
            'preferences': <String, dynamic>{},
          }),
        );
        expect(preview.eventCount, 1);
        expect(WhatWorkedStats.fromEvents(preview.events).total, 0);
      }
    });
  });
}
