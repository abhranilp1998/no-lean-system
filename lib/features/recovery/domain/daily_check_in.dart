import 'dart:convert';

import 'notification_policy.dart';
import 'risk_window.dart';

/// Daily check-in notification: one tap answers Okay, Struggling or Used.
///
/// Storage is two optional keys in the existing state map (`dailyCheckIn`,
/// `dailyCheckInMinutes`), so no state or backup version bump is needed.
/// Missing keys mean "off, 20:00".
///
/// Wording for PR #33 (private notifications): [dailyCheckInCopy] already
/// returns a neutral variant when `hideSensitive` is set, with no word from
/// #33's `sensitiveNotificationWords`. After #33 merges, add
/// [dailyCheckInChannel] to `NotificationChannels` and build a
/// `dailyCheckInSurface()` from [dailyCheckInCopy] in
/// `everyFlutterNotificationSurface`, so its test covers this surface too.
const dailyCheckInId = 730;

/// 20:00, the default "evening".
const defaultCheckInMinutes = 20 * 60;

/// Channel metadata for the PR #33 catalogue. The id must stay stable.
const dailyCheckInChannel = (
  id: 'daily_check_in_v1',
  publicName: 'NO LEAN daily check-in',
  publicDescription: 'A once-a-day check-in you can answer from the shade',
  privateName: 'Daily check-in',
  privateDescription: 'A once-a-day reminder',
);

/// Action ids. The first two run in the background without opening the app.
const checkInOkayAction = 'action_checkin_okay';
const checkInUsedAction = 'action_checkin_used';

/// Used while the relapse lock is on: opens the app so the lock can ask.
const checkInUsedOpenAction = 'action_checkin_used_open';

/// Opens the app to the urge tools.
const checkInStrugglingAction = 'action_checkin_struggling';

enum CheckInAnswer { okay, used }

class DailyCheckInCopy {
  const DailyCheckInCopy({
    required this.title,
    required this.body,
    required this.okayLabel,
    required this.strugglingLabel,
    required this.usedLabel,
  });

  final String title;
  final String body;
  final String okayLabel;
  final String strugglingLabel;
  final String usedLabel;

  List<String> get visibleStrings => [
    title,
    body,
    okayLabel,
    strugglingLabel,
    usedLabel,
  ];
}

DailyCheckInCopy dailyCheckInCopy({required bool hideSensitive}) =>
    hideSensitive
    ? const DailyCheckInCopy(
        title: 'Daily check-in',
        body: 'How is today going?',
        okayLabel: 'GOOD',
        strugglingLabel: 'ROUGH',
        usedLabel: 'SLIPPED',
      )
    : const DailyCheckInCopy(
        title: 'DAILY CHECK-IN',
        body: 'How is today going? One tap: Okay, Struggling, or Used.',
        okayLabel: 'OKAY',
        strugglingLabel: 'STRUGGLING',
        usedLabel: 'USED',
      );

/// Whether the daily time sits inside quiet hours (then it is not sent).
bool checkInInQuietHours(NotificationPrefs prefs, int minutes) {
  final normalized = minutes % RiskWindow.minutesPerDay;
  return !prefs.allows(
    NotificationKind.dailyCheckIn,
    DateTime(2026, 1, 5, normalized ~/ 60, normalized % 60),
  );
}

/// Settings subtitle: off, the time, or why it will stay quiet.
String dailyCheckInSubtitle({
  required bool enabled,
  required int minutes,
  required NotificationPrefs prefs,
}) {
  if (!enabled) return 'Off // one-tap Okay / Struggling / Used each day';
  final at = RiskWindow.formatMinutes(minutes);
  if (checkInInQuietHours(prefs, minutes)) {
    return 'On // $at is inside quiet hours, so it will not be sent';
  }
  return 'Every day at $at // Okay, Struggling or Used in one tap';
}

/// One answer left by the background isolate.
class CheckInEntry {
  const CheckInEntry({
    required this.id,
    required this.answer,
    required this.at,
  });

  final String id;
  final CheckInAnswer answer;

  /// When the button was tapped; becomes the event's occurredAt.
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'id': id,
    'answer': answer.name,
    'at': at.toIso8601String(),
  };

  static CheckInEntry? tryDecode(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final answer = CheckInAnswer.values
        .where((value) => value.name == json['answer'])
        .firstOrNull;
    final at = json['at'] is String ? DateTime.tryParse(json['at']) : null;
    if (id is! String || id.isEmpty || answer == null || at == null) {
      return null;
    }
    return CheckInEntry(id: id, answer: answer, at: at);
  }

  String encode() => jsonEncode(toJson());
}

/// Maps a notification action id to a background answer.
CheckInAnswer? checkInAnswerFor(String? actionId) => switch (actionId) {
  checkInOkayAction => CheckInAnswer.okay,
  checkInUsedAction => CheckInAnswer.used,
  _ => null,
};

/// Reads the optional minute-of-day; anything invalid falls back.
int checkInMinutesFrom(Object? value, int fallback) =>
    value is int && value >= 0 && value < RiskWindow.minutesPerDay
    ? value
    : fallback;

/// Used placeholders waiting for details.
const needsDetailsKey = 'needsDetails';
