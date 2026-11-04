import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';
import 'package:no_lean/features/recovery/domain/use_check.dart';
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

  test(
    'craving and SOS start (even with no outcome) queue the check',
    () async {
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
      await c.startSosSession();
      expect(queued.single.trigger, UseCheckTrigger.sos);
      await c.recordCraving(
        CravingEntry(
          createdAt: DateTime.now(),
          intensity: 6,
          trigger: 'Other',
          note: '',
        ),
      );
      expect(queued.last.trigger, UseCheckTrigger.craving);
    },
  );
}
