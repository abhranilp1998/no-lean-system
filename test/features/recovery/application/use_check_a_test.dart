import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';
import 'package:no_lean/features/recovery/domain/use_check.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';
import 'package:no_lean/features/withdrawal/domain/withdrawal_guide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final t = DateTime(2026, 11, 4, 21);

  test('delays sit in the 30–60 min window', () {
    for (final trigger in UseCheckTrigger.values) {
      final m = trigger.delay.inMinutes;
      expect(m, inInclusiveRange(30, 60), reason: trigger.name);
    }
  });

  test('encode/decode round-trip; junk decodes to null', () {
    final c = UseCheck(trigger: UseCheckTrigger.zoneExit, triggeredAt: t);
    final back = UseCheck.decode(c.encode())!;
    expect(back.trigger, UseCheckTrigger.zoneExit);
    expect(back.triggeredAt, t);
    expect(back.dueAt, t.add(const Duration(minutes: 30)));
    expect(UseCheck.decode('nope'), isNull);
    expect(UseCheck.decode(null), isNull);
  });

  test('YES prefill is the trigger time, never the future', () {
    final c = UseCheck(trigger: UseCheckTrigger.sos, triggeredAt: t);
    expect(useCheckPrefill(c, t.add(const Duration(hours: 1))), t);
    expect(
      useCheckPrefill(c, t.subtract(const Duration(hours: 1))),
      t.subtract(const Duration(hours: 1)),
    );
  });

  test('withdrawal spike = severe symptom or red flag', () {
    expect(
      isWithdrawalSpike(SymptomCheckIn(at: t, severities: {Symptom.aches: 2})),
      isFalse,
    );
    expect(
      isWithdrawalSpike(SymptomCheckIn(at: t, severities: {Symptom.aches: 3})),
      isTrue,
    );
    expect(
      isWithdrawalSpike(
        SymptomCheckIn(at: t, severities: {Symptom.cantKeepFluids: 1}),
      ),
      isTrue,
    );
  });

  group('controller lifecycle of check 740', () {
    late List<UseCheck> queued;
    late int cancels;
    late RecoveryController c;
    setUp(() async {
      queued = [];
      cancels = 0;
      c = RecoveryController(
        relapseLock: FakeRelapseLock(),
        scheduleCravingCheck: (_) async => true,
        cancelCravingCheck: () async {},
        scheduleUseCheck: (check) async {
          queued.add(check);
          return true;
        },
        cancelUseCheck: () async => cancels++,
      );
      await c.load();
    });

    test('SOS start does not queue; ending with no outcome does', () async {
      final id = await c.startSosSession();
      await pumpEventQueue();
      expect(queued, isEmpty);
      final end = DateTime.now();
      await c.completeSosSession(startId: id, completedAt: end);
      await pumpEventQueue();
      expect(queued.single.trigger, UseCheckTrigger.sos);
      expect(queued.single.triggeredAt, end);
      expect(cancels, 0);
    });

    test('SOS ending with an outcome cancels the check', () async {
      final id = await c.startSosSession();
      await c.completeSosSession(
        startId: id,
        completedAt: DateTime.now(),
        debrief: 'urge passed',
      );
      await pumpEventQueue();
      expect(queued, isEmpty);
      expect(cancels, 1);
    });

    test('logging a relapse cancels the check', () async {
      await c.recordCraving(
        CravingEntry(
          createdAt: DateTime.now(),
          intensity: 6,
          trigger: 'Other',
          note: '',
        ),
      );
      await c.quickLogUsed();
      await pumpEventQueue();
      expect(queued.single.trigger, UseCheckTrigger.craving);
      expect(cancels, 1);
    });

    test('a denied relapse save does not cancel', () async {
      await c.enableRelapseLock('2468');
      final r = await c.recordRelapse(pin: '1111', tryBiometrics: false);
      await pumpEventQueue();
      expect(r, ProtectedActionResult.denied);
      expect(cancels, 0);
    });
  });

  test('body tap on 740 maps to the prompt; buttons keep their id', () {
    expect(
      NotificationService.actionFor(null, NotificationService.useCheckId),
      NotificationService.useCheckOpenAction,
    );
    expect(
      NotificationService.actionFor('action_use_yes', 740),
      'action_use_yes',
    );
    expect(NotificationService.actionFor(null, 12), isNull);
  });

  test('a craving queues the check', () async {
    final queued = <UseCheck>[];
    final c = RecoveryController(
      relapseLock: FakeRelapseLock(),
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
      scheduleUseCheck: (check) async {
        queued.add(check);
        return true;
      },
    );
    await c.load();
    await c.recordCraving(
      CravingEntry(
        createdAt: DateTime.now(),
        intensity: 6,
        trigger: 'Other',
        note: '',
      ),
    );
    expect(queued.last.trigger, UseCheckTrigger.craving);
  });
}
