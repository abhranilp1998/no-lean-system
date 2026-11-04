// Plan P0-4: the post-relapse cooldown expires by time and is reconciled on
// load. A stale `relapseCooldownEventId` (deadline passed, or its event gone,
// e.g. the Oct 25 one in real backups) used to block every later cooldown.

import 'recovery_event.dart';

class CooldownState {
  const CooldownState(this.until, this.eventId);
  const CooldownState.none() : until = null, eventId = null;

  final DateTime? until;
  final String? eventId;

  bool get isActive => until != null;
}

/// Pure: keeps the cooldown only while its deadline is in the future and
/// (when it names one) its relapse event still exists.
CooldownState reconcileCooldown({
  required DateTime? until,
  required String? eventId,
  required Iterable<RecoveryEvent> events,
  required DateTime now,
}) {
  if (until == null || !until.isAfter(now)) return const CooldownState.none();
  if (eventId != null &&
      !events.any(
        (e) => e.id == eventId && e.type == RecoveryEventType.relapse,
      )) {
    return const CooldownState.none();
  }
  return CooldownState(until, eventId);
}
