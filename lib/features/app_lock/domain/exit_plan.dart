// The emergency exit plan for locked apps (user instruction, Oct 2026):
// legitimate needs, such as paying inside a danger zone, must always stay
// possible. A locked app is never a dead end:
//
// 1. "I need this app" -> pick a reason.
// 2. Within the daily budget: a mindful wait showing the user's own reasons
//    (30 s; payment apps 10 s), then that app only opens for 5 minutes.
// 3. Budget used up: the existing PIN (or biometrics) with its lockout rules.
// 4. No PIN set, or PIN entry paused by a lockout: a long 120 s wait still
//    opens the app. SOS, Call 112 and Go home are always on the screen.

import '../../recovery/domain/recovery_event.dart';

/// Why the user needs a locked app right now.
enum UnlockReason { payment, work, navigation, urgent, other }

extension UnlockReasonLabel on UnlockReason {
  String get label => switch (this) {
    UnlockReason.payment => 'Payment',
    UnlockReason.work => 'Work',
    UnlockReason.navigation => 'Navigation',
    UnlockReason.urgent => 'Urgent',
    UnlockReason.other => 'Other',
  };

  static UnlockReason? fromName(Object? name) =>
      UnlockReason.values.where((value) => value.name == name).firstOrNull;
}

/// How an unlock was earned. Stored on the `appUnlock` event.
enum UnlockMethod {
  /// Mindful wait within the daily budget.
  budget,

  /// Budget used up: verified with the PIN or biometrics.
  pin,

  /// Budget used up and no PIN available (none set or locked out).
  longWait,
}

/// One step of the exit plan, decided by [planUnlock].
class ExitStep {
  const ExitStep({
    required this.method,
    required this.wait,
    required this.unlockFor,
  });

  final UnlockMethod method;

  /// Mindful wait before the app opens (zero for the PIN path).
  final Duration wait;

  /// How long the temporary unlock lasts (that app only).
  final Duration unlockFor;

  bool get needsPin => method == UnlockMethod.pin;
}

abstract final class ExitPlanTimings {
  static const standardWait = Duration(seconds: 30);
  static const paymentWait = Duration(seconds: 10);
  static const longWait = Duration(seconds: 120);
  static const unlockFor = Duration(minutes: 5);
}

/// Decides the next step. Pure, so the whole plan is unit-tested.
ExitStep planUnlock({
  required bool paymentApp,
  required int usedToday,
  required int dailyBudget,
  required bool pinConfigured,
  bool pinLockedOut = false,
}) {
  if (usedToday < dailyBudget) {
    return ExitStep(
      method: UnlockMethod.budget,
      wait: paymentApp
          ? ExitPlanTimings.paymentWait
          : ExitPlanTimings.standardWait,
      unlockFor: ExitPlanTimings.unlockFor,
    );
  }
  if (pinConfigured && !pinLockedOut) {
    return const ExitStep(
      method: UnlockMethod.pin,
      wait: Duration.zero,
      unlockFor: ExitPlanTimings.unlockFor,
    );
  }
  return const ExitStep(
    method: UnlockMethod.longWait,
    wait: ExitPlanTimings.longWait,
    unlockFor: ExitPlanTimings.unlockFor,
  );
}

/// Budget unlocks used on [now]'s local calendar day. PIN and long-wait
/// unlocks don't spend the budget.
int unlocksUsedOn(Iterable<RecoveryEvent> events, DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  final next = DateTime(now.year, now.month, now.day + 1);
  return events.where((event) {
    if (event.type != RecoveryEventType.appUnlock) return false;
    if (event.metadata['method'] != UnlockMethod.budget.name) return false;
    final at = event.timestamp.toLocal();
    return !at.isBefore(day) && at.isBefore(next);
  }).length;
}

/// Metadata for the `appUnlock` timeline event. Never coordinates.
Map<String, Object> appUnlockMetadata({
  required String packageName,
  required String appLabel,
  required UnlockReason reason,
  required ExitStep step,
  required bool paymentApp,
  String? zoneName,
}) => {
  'packageName': packageName,
  'appLabel': appLabel,
  'reason': reason.name,
  'method': step.method.name,
  'waitSeconds': step.wait.inSeconds,
  'unlockMinutes': step.unlockFor.inMinutes,
  'paymentApp': paymentApp,
  if (zoneName != null && zoneName.trim().isNotEmpty)
    'zoneName': zoneName.trim(),
};
