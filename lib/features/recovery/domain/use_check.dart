import 'dart:convert';

import '../../withdrawal/domain/withdrawal_guide.dart';

/// (A) Follow-up "Did you use?" check-in, asked a while after a risky moment.
enum UseCheckTrigger {
  craving,
  sos,
  zoneExit,
  withdrawalSpike,
  aboutToUse,

  /// A visit to a saved danger zone. The check comes an hour after arriving,
  /// so the visit is over by then. See zone_use_check.dart for the limits.
  zoneVisit,
}

extension UseCheckTriggerCopy on UseCheckTrigger {
  Duration get delay => switch (this) {
    UseCheckTrigger.craving => const Duration(minutes: 45),
    UseCheckTrigger.sos => const Duration(minutes: 45),
    UseCheckTrigger.zoneExit => const Duration(minutes: 30),
    UseCheckTrigger.withdrawalSpike => const Duration(minutes: 60),
    UseCheckTrigger.aboutToUse => const Duration(minutes: 45),
    UseCheckTrigger.zoneVisit => const Duration(minutes: 60),
  };

  /// Zone checks have their own card, wording and "zone resisted" count.
  bool get isZoneCheck =>
      this == UseCheckTrigger.zoneVisit || this == UseCheckTrigger.zoneExit;

  String get notificationTitle =>
      this == UseCheckTrigger.zoneVisit ? 'CHECKING IN' : 'DID YOU USE?';

  String get body => switch (this) {
    UseCheckTrigger.craving => 'You logged a craving a while ago.',
    UseCheckTrigger.sos => 'You opened SOS a while ago.',
    UseCheckTrigger.zoneExit => 'You left a danger zone a while ago.',
    UseCheckTrigger.withdrawalSpike => 'Withdrawal was rough a while ago.',
    UseCheckTrigger.aboutToUse => 'You said you might use a while ago.',
    // Never names the place: a lock-screen notification can be read by
    // someone else.
    UseCheckTrigger.zoneVisit => 'You were somewhere tough a while ago.',
  };
}

/// One pending check at a time; a newer risky moment replaces an older one.
class UseCheck {
  const UseCheck({
    required this.trigger,
    required this.triggeredAt,
    this.zoneId,
    this.zoneName,
    this.snoozes = 0,
    this.snoozedUntil,
  });

  final UseCheckTrigger trigger;

  /// When the risky moment happened. For a zone visit: when the user arrived.
  final DateTime triggeredAt;

  /// Zone visit only. Kept on this device until the check is answered, and
  /// only when the user keeps zone history on (see the controller).
  final String? zoneId;
  final String? zoneName;

  /// How many times "later" was chosen, and until when it is snoozed.
  final int snoozes;
  final DateTime? snoozedUntil;

  DateTime get dueAt => snoozedUntil ?? triggeredAt.add(trigger.delay);

  bool isDue(DateTime now) => !now.isBefore(dueAt);

  UseCheck snoozed(DateTime now) => UseCheck(
    trigger: trigger,
    triggeredAt: triggeredAt,
    zoneId: zoneId,
    zoneName: zoneName,
    snoozes: snoozes + 1,
    snoozedUntil: now.add(useCheckSnooze),
  );

  String encode() => jsonEncode({
    'trigger': trigger.name,
    'triggeredAt': triggeredAt.toIso8601String(),
    if (zoneId != null) 'zoneId': zoneId,
    if (zoneName != null) 'zoneName': zoneName,
    if (snoozes > 0) 'snoozes': snoozes,
    if (snoozedUntil != null) 'snoozedUntil': snoozedUntil!.toIso8601String(),
  });

  static UseCheck? decode(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final trigger = UseCheckTrigger.values.byName(map['trigger'] as String);
      final at = DateTime.parse(map['triggeredAt'] as String);
      final until = map['snoozedUntil'];
      return UseCheck(
        trigger: trigger,
        triggeredAt: at,
        zoneId: map['zoneId'] as String?,
        zoneName: map['zoneName'] as String?,
        snoozes: (map['snoozes'] as num?)?.toInt() ?? 0,
        snoozedUntil: until is String ? DateTime.parse(until) : null,
      );
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
