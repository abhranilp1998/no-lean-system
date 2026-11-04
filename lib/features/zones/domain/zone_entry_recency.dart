import '../../recovery/domain/notification_policy.dart';
import '../../recovery/domain/recovery_event.dart';

/// A zone entry older than this is history, not something to react to: it
/// never reopens the full-screen alert or schedules follow-ups.
const zoneEntryMaxAge = Duration(minutes: 30);

/// The latest zone entry within [zoneEntryMaxAge] of [now], if any.
RecoveryEvent? recentZoneEntry(Iterable<RecoveryEvent> events, DateTime now) {
  RecoveryEvent? latest;
  for (final e in events) {
    if (e.type != RecoveryEventType.zoneEntry) continue;
    final age = now.difference(e.timestamp);
    if (age.isNegative || age > zoneEntryMaxAge) continue;
    if (latest == null || e.timestamp.isAfter(latest.timestamp)) latest = e;
  }
  return latest;
}

/// Follow-up copy after a zone entry. Goes through [NotificationPrefs.textFor]
/// so privacy mode posts the neutral text, never the zone name.
NotificationText zoneFollowUpText(
  NotificationPrefs prefs,
  int index,
  String zoneName,
) => prefs.textFor(
  'CHECKING IN',
  index == 0
      ? 'It\'s been 15 minutes since $zoneName. Still OK? Tap if you need SOS.'
      : 'Quick check: how are you doing after $zoneName? No judgement either way.',
);
