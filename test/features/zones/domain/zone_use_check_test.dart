import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/domain/use_check.dart';
import 'package:no_lean/features/zones/domain/zone_entry.dart';
import 'package:no_lean/features/zones/domain/zone_use_check.dart';

ZoneEntry visit(DateTime at, {String zone = 'z1'}) =>
    ZoneEntry(zoneId: zone, zoneName: 'Old bar', at: at, source: 'app');

void main() {
  final t = DateTime(2026, 11, 20, 21);
  const empty = ZoneUseCheckLedger();

  group('who gets asked', () {
    test('a fresh visit is asked about', () {
      expect(empty.decide(visit(t), t), ZoneUseCheckDecision.ask);
    });

    test('a visit older than 24h is not asked about', () {
      expect(
        empty.decide(visit(t), t.add(const Duration(hours: 25))),
        ZoneUseCheckDecision.stale,
      );
    });

    test('the same visit reported twice (app + geofence) is one question', () {
      final ledger = empty.withVisit(visit(t), t);
      expect(
        ledger.decide(visit(t.add(const Duration(minutes: 5))), t),
        ZoneUseCheckDecision.alreadyAsked,
      );
    });

    test('same zone again inside 4h waits, and is asked after 4h', () {
      final ledger = empty.withVisit(visit(t), t);
      expect(
        ledger.decide(visit(t.add(const Duration(hours: 2))), t),
        ZoneUseCheckDecision.zoneCooldown,
      );
      expect(
        ledger.decide(visit(t.add(const Duration(hours: 5))), t),
        ZoneUseCheckDecision.ask,
      );
    });

    test('a different zone inside 90 min waits, after that it is asked', () {
      final ledger = empty.withVisit(visit(t), t);
      expect(
        ledger.decide(visit(t.add(const Duration(minutes: 40)), zone: 'z2'), t),
        ZoneUseCheckDecision.anyCooldown,
      );
      expect(
        ledger.decide(
          visit(t.add(const Duration(minutes: 100)), zone: 'z2'),
          t,
        ),
        ZoneUseCheckDecision.ask,
      );
    });

    test('at most three questions in 24 hours', () {
      var ledger = empty;
      for (var i = 0; i < zoneUseCheckDailyMax; i++) {
        final at = t.add(Duration(hours: i * 2));
        expect(
          ledger.decide(visit(at, zone: 'z$i'), at),
          ZoneUseCheckDecision.ask,
        );
        ledger = ledger.withVisit(visit(at, zone: 'z$i'), at);
      }
      final fourth = t.add(const Duration(hours: 7));
      expect(
        ledger.decide(visit(fourth, zone: 'z9'), fourth),
        ZoneUseCheckDecision.dailyLimit,
      );
    });

    test('ledger survives encode/decode; junk decodes to empty', () {
      final ledger = empty.withVisit(visit(t), t);
      final back = ZoneUseCheckLedger.decode(ledger.encode());
      expect(back.asked.single.zoneId, 'z1');
      expect(back.asked.single.at, t);
      expect(ZoneUseCheckLedger.decode('nope').asked, isEmpty);
      expect(ZoneUseCheckLedger.decode(null).asked, isEmpty);
    });

    test('old ledger entries are pruned after 2 days', () {
      final ledger = empty.withVisit(visit(t), t);
      final later = t.add(const Duration(days: 3));
      final next = ledger.withVisit(visit(later, zone: 'z2'), later);
      expect(next.asked.map((a) => a.zoneId), ['z2']);
    });
  });

  group('the check itself', () {
    test('comes an hour after arriving, and only then is it due', () {
      final check = UseCheck(
        trigger: UseCheckTrigger.zoneVisit,
        triggeredAt: t,
      );
      expect(check.dueAt, t.add(const Duration(hours: 1)));
      expect(check.isDue(t.add(const Duration(minutes: 59))), isFalse);
      expect(check.isDue(t.add(const Duration(hours: 1))), isTrue);
      expect(UseCheckTrigger.zoneVisit.isZoneCheck, isTrue);
      expect(UseCheckTrigger.craving.isZoneCheck, isFalse);
    });

    test('snooze is 30 min, counted, and runs out after two', () {
      final now = t.add(const Duration(hours: 1));
      var check = UseCheck(trigger: UseCheckTrigger.zoneVisit, triggeredAt: t);
      check = check.snoozed(now);
      expect(check.snoozes, 1);
      expect(check.dueAt, now.add(useCheckSnooze));
      expect(check.isDue(now.add(const Duration(minutes: 29))), isFalse);
      expect(zoneCheckExhausted(check), isFalse);
      check = check.snoozed(now);
      expect(zoneCheckExhausted(check), isTrue);
    });

    test('expires 24h after the visit', () {
      final check = UseCheck(
        trigger: UseCheckTrigger.zoneVisit,
        triggeredAt: t,
      );
      expect(
        zoneCheckExpired(check, t.add(const Duration(hours: 23))),
        isFalse,
      );
      expect(zoneCheckExpired(check, t.add(const Duration(hours: 25))), isTrue);
    });

    test('zone fields and snooze survive encode/decode', () {
      final check = UseCheck(
        trigger: UseCheckTrigger.zoneVisit,
        triggeredAt: t,
        zoneId: 'z1',
        zoneName: 'Old bar',
      ).snoozed(t.add(const Duration(hours: 1)));
      final back = UseCheck.decode(check.encode())!;
      expect(back.zoneId, 'z1');
      expect(back.zoneName, 'Old bar');
      expect(back.snoozes, 1);
      expect(back.snoozedUntil, check.snoozedUntil);
    });

    test('a check saved by an older app (no zone fields) still decodes', () {
      final old = jsonEncode({
        'trigger': 'zoneExit',
        'triggeredAt': t.toIso8601String(),
      });
      final back = UseCheck.decode(old)!;
      expect(back.trigger, UseCheckTrigger.zoneExit);
      expect(back.zoneName, isNull);
      expect(back.snoozes, 0);
      expect(back.dueAt, t.add(const Duration(minutes: 30)));
    });
  });

  group('copy', () {
    final check = UseCheck(
      trigger: UseCheckTrigger.zoneVisit,
      triggeredAt: t,
      zoneName: 'Old bar',
    );

    test('the notification never names the place', () {
      expect(UseCheckTrigger.zoneVisit.body, isNot(contains('Old bar')));
      expect(
        UseCheckTrigger.zoneVisit.body.toLowerCase(),
        isNot(contains('zone')),
      );
    });

    test('the card names the place only when we have it', () {
      expect(zoneCheckBody(check), contains('Old bar'));
      final anon = UseCheck(trigger: UseCheckTrigger.zoneVisit, triggeredAt: t);
      expect(zoneCheckBody(anon), contains('a tough spot'));
    });

    test('warm, non-judgmental, no helplines or numbers', () {
      final all = [
        zoneCheckHeadline(check),
        zoneCheckBody(check),
        zoneResistedMessage(1),
        zoneResistedMessage(4),
        zoneCheckSnoozedMessage,
        zoneCheckDroppedMessage,
        zoneCheckPrefillNote(check),
        UseCheckTrigger.zoneVisit.body,
      ].join(' ').toLowerCase();
      for (final word in [
        'failed',
        'failure',
        'helpline',
        'hotline',
        '112',
        '911',
        'call ',
      ]) {
        expect(all, isNot(contains(word)), reason: word);
      }
      expect(zoneResistedMessage(1), contains('One zone resisted'));
      expect(zoneResistedMessage(4), contains('4 zones resisted'));
    });

    test('prefill note is long enough for the logger (12+ chars)', () {
      expect(zoneCheckPrefillNote(check).length, greaterThanOrEqualTo(12));
      final anon = UseCheck(trigger: UseCheckTrigger.zoneVisit, triggeredAt: t);
      expect(zoneCheckPrefillNote(anon).length, greaterThanOrEqualTo(12));
    });
  });

  group('quiet hours', () {
    const quiet = NotificationPrefs(
      quietHoursEnabled: true,
      quietHours: RiskWindow(startMinutes: 22 * 60, endMinutes: 7 * 60),
    );

    test('the follow-up is muted in quiet hours, not at other times', () {
      final due = DateTime(2026, 11, 20, 23);
      expect(quiet.allows(NotificationKind.cravingCheck, due), isFalse);
      expect(
        quiet.allows(NotificationKind.cravingCheck, DateTime(2026, 11, 20, 15)),
        isTrue,
      );
    });
  });
}
