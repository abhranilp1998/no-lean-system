import '../../recovery/domain/event_derived_state.dart';
import '../../recovery/domain/notification_policy.dart';
import '../../recovery/domain/recovery_event.dart';

/// How long the calm home stays up unless the user leaves it earlier.
const roughDayDuration = Duration(hours: 24);

/// Default wait before the "log it later" nudge.
const logLaterDelay = Duration(hours: 2);

/// Visits or slips older than this do not start a rough day.
const roughDaySlipMaxAge = Duration(hours: 24);

enum RoughDaySource { slip, struggling }

/// Optional persisted rough-day fields. Missing keys mean "not in a rough day",
/// so older saves and backups keep working with no version bump.
class RoughDayState {
  const RoughDayState({
    required this.startedAt,
    required this.until,
    required this.source,
  });

  final DateTime startedAt;
  final DateTime until;
  final RoughDaySource source;

  bool isActive(DateTime now) => now.isBefore(until);

  Map<String, dynamic> toJson() => {
    'roughDayStartedAt': startedAt.toIso8601String(),
    'roughDayUntil': until.toIso8601String(),
    'roughDaySource': source.name,
  };

  /// Returns null when the map has no usable rough-day fields (old state).
  static RoughDayState? fromJson(Map<String, dynamic>? map) {
    if (map == null) return null;
    final until = DateTime.tryParse(map['roughDayUntil']?.toString() ?? '');
    final started =
        DateTime.tryParse(map['roughDayStartedAt']?.toString() ?? '') ?? until;
    if (until == null || started == null) return null;
    final sourceName = map['roughDaySource']?.toString();
    final source = RoughDaySource.values
        .where((s) => s.name == sourceName)
        .firstOrNull;
    return RoughDayState(
      startedAt: started,
      until: until,
      source: source ?? RoughDaySource.slip,
    );
  }
}

/// A recent logged slip can open a rough day; a historical one cannot.
bool shouldStartRoughDayForSlip({
  required DateTime occurredAt,
  required DateTime now,
}) {
  final age = now.difference(occurredAt);
  // A one-tap "I used" is stamped with the wall clock, which can be a
  // second ahead of a test (or slightly-skewed) clock.
  if (age.isNegative) return age.abs() <= const Duration(minutes: 2);
  return age <= roughDaySlipMaxAge;
}

/// The lean clean timer is still running after a recent benzo-only slip.
bool leanTimerIntactAfterRecentSlip({
  required List<RecoveryEvent> events,
  required DateTime now,
}) {
  RecoveryEvent? latest;
  for (final event in events) {
    if (event.type != RecoveryEventType.relapse) continue;
    if (now.difference(event.timestamp) > roughDaySlipMaxAge) continue;
    if (latest == null || event.timestamp.isAfter(latest.timestamp)) {
      latest = event;
    }
  }
  return latest != null && !resetsLeanCleanTimer(latest);
}

int _rodeOutCount(List<RecoveryEvent> events) => events
    .where(
      (e) =>
          e.type == RecoveryEventType.cravingCheck &&
          (e.metadata['outcome'] == 'gone' || e.metadata['outcome'] == 'eased'),
    )
    .length;

/// Warm, first-person-to-the-user copy, built from their own logs.
class RoughDayCopy {
  const RoughDayCopy({required this.headline, required this.body});

  final String headline;
  final String body;
}

const _headlines = [
  'This is a rough day. You are still here.',
  'You do not have to be okay right now.',
  'One moment does not undo you.',
];

const _fallbackBody =
    'Three things, whenever you are ready. No rush, and no judgment.';

RoughDayCopy roughDayCopy({
  required List<RecoveryEvent> events,
  required DateTime now,
  required int longestStreak,
  int seed = 0,
}) {
  final headline = _headlines[seed.abs() % _headlines.length];
  final rode = _rodeOutCount(events);
  final String body;
  if (leanTimerIntactAfterRecentSlip(events: events, now: now)) {
    body = 'Your lean clean time is still running. That still counts.';
  } else if (longestStreak >= 1) {
    body = longestStreak == 1
        ? 'You already built a 1-day stretch. That work is still yours.'
        : 'You already built a $longestStreak-day stretch. That work is still yours.';
  } else if (rode >= 1) {
    body = rode == 1
        ? 'You have ridden a craving out before. You can do it again.'
        : 'You have ridden $rode cravings out before. You can do it again.';
  } else {
    body = _fallbackBody;
  }
  return RoughDayCopy(headline: headline, body: body);
}

const roughDayCallLabel = 'CALL MY PERSON';
const roughDayRideLabel = 'RIDE IT OUT';
const roughDayLogLaterLabel = 'LOG IT LATER';
const roughDayBackLabel = 'Back to normal view';
const roughDayImStrugglingTitle = "I'M STRUGGLING";
const roughDayImStrugglingSubtitle =
    'A calmer home, and three things that help';

const roughDayCallEmptyMessage =
    'Add someone you trust first. I will only call the number you give me.';

const roughDayLogLaterPrompt =
    'You do not have to write it down now. I can nudge you in a couple of hours, or you can log it here.';

const roughDayRemindLabel = 'REMIND ME IN 2 HOURS';
const roughDayLogNowLabel = 'WRITE IT DOWN NOW';

String roughDayReminderSetMessage(DateTime at) {
  final hour = at.hour.toString().padLeft(2, '0');
  final minute = at.minute.toString().padLeft(2, '0');
  return 'Okay. I will nudge you around $hour:$minute. Only if you want to write then.';
}

const roughDayReminderFailedMessage =
    'I could not set a reminder, but you can still write it down whenever you are ready.';

const logLaterNotificationTitle = 'WHEN YOU ARE READY';
const logLaterNotificationBody =
    'You can write down what happened whenever it feels okay.';

/// If [at] falls inside quiet hours, move it to the first minute after they
/// end. Critical notifications are never deferred this way; the log-later
/// nudge is not critical.
DateTime deferPastQuietHours(NotificationPrefs prefs, DateTime at) {
  if (prefs.allows(NotificationKind.logReminder, at)) return at;
  final end = prefs.quietHours.endMinutes;
  var candidate = DateTime(
    at.year,
    at.month,
    at.day,
    end ~/ 60,
    end % 60,
  ).add(const Duration(minutes: 1));
  if (!candidate.isAfter(at)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}
