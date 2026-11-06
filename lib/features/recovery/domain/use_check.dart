import 'dart:convert';

import '../../withdrawal/domain/withdrawal_guide.dart';

/// (A) Follow-up "Did you use?" check-in, asked a while after a risky moment.
enum UseCheckTrigger { craving, sos, zoneExit, withdrawalSpike, aboutToUse }

extension UseCheckTriggerCopy on UseCheckTrigger {
  Duration get delay => switch (this) {
    UseCheckTrigger.craving => const Duration(minutes: 45),
    UseCheckTrigger.sos => const Duration(minutes: 45),
    UseCheckTrigger.zoneExit => const Duration(minutes: 30),
    UseCheckTrigger.withdrawalSpike => const Duration(minutes: 60),
    UseCheckTrigger.aboutToUse => const Duration(minutes: 45),
  };

  String get body => switch (this) {
    UseCheckTrigger.craving => 'You logged a craving a while ago.',
    UseCheckTrigger.sos => 'You opened SOS a while ago.',
    UseCheckTrigger.zoneExit => 'You left a danger zone a while ago.',
    UseCheckTrigger.withdrawalSpike => 'Withdrawal was rough a while ago.',
    UseCheckTrigger.aboutToUse => 'You said you might use a while ago.',
  };
}

/// One pending check at a time; a newer risky moment replaces an older one.
class UseCheck {
  const UseCheck({required this.trigger, required this.triggeredAt});

  final UseCheckTrigger trigger;
  final DateTime triggeredAt;

  DateTime get dueAt => triggeredAt.add(trigger.delay);

  String encode() => jsonEncode({
    'trigger': trigger.name,
    'triggeredAt': triggeredAt.toIso8601String(),
  });

  static UseCheck? decode(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final trigger = UseCheckTrigger.values.byName(map['trigger'] as String);
      final at = DateTime.parse(map['triggeredAt'] as String);
      return UseCheck(trigger: trigger, triggeredAt: at);
    } catch (_) {
      return null;
    }
  }
}

/// What a "Yes" prefills: the trigger time, since the use most likely came
/// right after it. Never in the future.
DateTime useCheckPrefill(UseCheck check, DateTime now) =>
    check.triggeredAt.isAfter(now) ? now : check.triggeredAt;

/// "Later" snoozes 30 minutes.
const useCheckSnooze = Duration(minutes: 30);

/// A check-in is a spike when any symptom is severe (3/3) or it has a red flag.
bool isWithdrawalSpike(SymptomCheckIn checkIn) =>
    checkIn.hasRedFlag || checkIn.severities.values.any((v) => v >= 3);
