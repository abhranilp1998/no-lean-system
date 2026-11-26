import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/dashboard/domain/rough_day.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/relapse_log_entry.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/domain/slip_tone.dart';

RecoveryEvent relapse(DateTime at, {RelapseType type = RelapseType.fullLean}) =>
    RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      timestamp: at,
      metadata: {'relapseType': type.name, 'recordedAt': at.toIso8601String()},
    );

void main() {
  final now = DateTime(2026, 11, 26, 21);

  group('when a slip starts a rough day', () {
    test('a slip from the last 24 hours does', () {
      expect(
        shouldStartRoughDayForSlip(
          occurredAt: now.subtract(const Duration(hours: 3)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a historical slip older than 24 hours does not', () {
      expect(
        shouldStartRoughDayForSlip(
          occurredAt: now.subtract(const Duration(hours: 25)),
          now: now,
        ),
        isFalse,
      );
    });

    test('a couple of minutes of clock skew still counts as now', () {
      expect(
        shouldStartRoughDayForSlip(
          occurredAt: now.add(const Duration(seconds: 30)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a time clearly in the future is refused', () {
      expect(
        shouldStartRoughDayForSlip(
          occurredAt: now.add(const Duration(hours: 3)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('state is optional and backwards compatible', () {
    test('a map with no rough-day keys decodes to nothing', () {
      expect(RoughDayState.fromJson({}), isNull);
      expect(RoughDayState.fromJson(null), isNull);
      expect(RoughDayState.fromJson({'stateVersion': 17}), isNull);
    });

    test('round-trips, and junk source falls back to slip', () {
      final state = RoughDayState(
        startedAt: now,
        until: now.add(roughDayDuration),
        source: RoughDaySource.struggling,
      );
      final back = RoughDayState.fromJson(state.toJson())!;
      expect(back.startedAt, now);
      expect(back.until, now.add(roughDayDuration));
      expect(back.source, RoughDaySource.struggling);
      expect(back.isActive(now.add(const Duration(hours: 23))), isTrue);
      expect(back.isActive(now.add(const Duration(hours: 25))), isFalse);

      final junk = RoughDayState.fromJson({
        'roughDayStartedAt': now.toIso8601String(),
        'roughDayUntil': now.add(roughDayDuration).toIso8601String(),
        'roughDaySource': 'nope',
      })!;
      expect(junk.source, RoughDaySource.slip);
    });

    test('an old backup-shaped map still decodes when mixed with events', () {
      final old =
          jsonDecode(
                jsonEncode({
                  'version': 8,
                  'events': [
                    {
                      'id': 'p-1',
                      'type': 'pledge',
                      'timestamp': DateTime(2026, 1, 1).toIso8601String(),
                      'metadata': <String, dynamic>{},
                    },
                  ],
                  'preferences': <String, dynamic>{},
                }),
              )
              as Map<String, dynamic>;
      expect(RoughDayState.fromJson(old), isNull);
      expect(
        RoughDayState.fromJson(old['preferences'] as Map<String, dynamic>),
        isNull,
      );
    });
  });

  group('copy', () {
    test('is warm, never judgmental, and never names a helpline or 112', () {
      final copies = [
        roughDayCopy(events: const [], now: now, longestStreak: 0, seed: 0),
        roughDayCopy(events: const [], now: now, longestStreak: 8, seed: 1),
        roughDayCopy(
          events: [
            relapse(
              now.subtract(const Duration(hours: 1)),
              type: RelapseType.benzo,
            ),
          ],
          now: now,
          longestStreak: 3,
          seed: 2,
        ),
        roughDayCopy(
          events: [
            RecoveryEvent.create(
              type: RecoveryEventType.cravingCheck,
              metadata: {
                'cravingId': 'c-1',
                'outcome': 'eased',
                'intensity': 3,
              },
            ),
          ],
          now: now,
          longestStreak: 0,
          seed: 0,
        ),
      ];
      final all = [
        ...copies.expand((c) => [c.headline, c.body]),
        roughDayCallEmptyMessage,
        roughDayLogLaterPrompt,
        roughDayReminderSetMessage(now),
        roughDayReminderFailedMessage,
        logLaterNotificationTitle,
        logLaterNotificationBody,
        roughDayBackLabel,
      ].join(' ').toLowerCase();
      for (final word in [
        'failed',
        'failure',
        'helpline',
        'hotline',
        '112',
        '911',
        'call 112',
        'ruined',
        'weak',
        'back to zero',
      ]) {
        expect(all, isNot(contains(word)), reason: word);
      }
      for (final c in copies) {
        expect(isWarmCopy(c.headline), isTrue, reason: c.headline);
        expect(isWarmCopy(c.body), isTrue, reason: c.body);
      }
    });

    test('a benzo-only slip talks about lean time still running', () {
      final copy = roughDayCopy(
        events: [
          relapse(
            now.subtract(const Duration(hours: 2)),
            type: RelapseType.benzo,
          ),
        ],
        now: now,
        longestStreak: 12,
      );
      expect(copy.body.toLowerCase(), contains('lean clean time'));
      expect(copy.body.toLowerCase(), contains('still'));
    });

    test('after a lean slip, it names their longest stretch', () {
      final copy = roughDayCopy(
        events: [relapse(now.subtract(const Duration(hours: 1)))],
        now: now,
        longestStreak: 12,
      );
      expect(copy.body, contains('12-day stretch'));
    });

    test('notification text never names the place, the drug, or a zone', () {
      expect(logLaterNotificationBody.toLowerCase(), isNot(contains('lean')));
      expect(logLaterNotificationBody.toLowerCase(), isNot(contains('zone')));
    });
  });

  group('quiet hours', () {
    const quiet = NotificationPrefs(
      quietHoursEnabled: true,
      quietHours: RiskWindow(startMinutes: 22 * 60, endMinutes: 7 * 60),
    );

    test('the nudge is muted in quiet hours and deferred until they end', () {
      final late = DateTime(2026, 11, 20, 23);
      expect(quiet.allows(NotificationKind.logReminder, late), isFalse);
      expect(deferPastQuietHours(quiet, late), DateTime(2026, 11, 21, 7, 1));
      final dawn = DateTime(2026, 11, 21, 6, 30);
      expect(deferPastQuietHours(quiet, dawn), DateTime(2026, 11, 21, 7, 1));
      final afternoon = DateTime(2026, 11, 21, 15);
      expect(quiet.allows(NotificationKind.logReminder, afternoon), isTrue);
      expect(deferPastQuietHours(quiet, afternoon), afternoon);
    });
  });
}
