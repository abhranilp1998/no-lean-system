import 'dart:convert';

import 'risk_window.dart';

/// Every notification NO LEAN can post.
enum NotificationKind {
  /// Risk-window interrupts. Critical: always delivered (user decision).
  riskWindow,

  /// Danger-zone entry. Critical: always delivered (user decision).
  dangerZone,

  /// Code Instead timer finished. Non-critical: muted in quiet hours.
  codeTimer,
}

extension NotificationKindPolicy on NotificationKind {
  bool get isCritical => switch (this) {
    NotificationKind.riskWindow || NotificationKind.dangerZone => true,
    NotificationKind.codeTimer => false,
  };
}

class NotificationText {
  const NotificationText({required this.title, required this.body});

  final String title;
  final String body;
}

/// Neutral wording used when "hide sensitive content" is on. Nothing here
/// names the substance, recovery, cravings, SOS or places.
const neutralNotificationText = NotificationText(
  title: 'Reminder',
  body: 'Open the app when you have a moment.',
);

/// User notification preferences.
class NotificationPrefs {
  const NotificationPrefs({
    this.quietHoursEnabled = false,
    this.quietHours = defaultQuietHours,
    this.hideSensitive = false,
  });

  static const defaultQuietHours = RiskWindow(
    startMinutes: 22 * 60,
    endMinutes: 7 * 60,
  );

  final bool quietHoursEnabled;
  final RiskWindow quietHours;
  final bool hideSensitive;

  bool inQuietHours(DateTime at) =>
      quietHoursEnabled && quietHours.contains(at);

  /// Critical kinds always pass; everything else is muted in quiet hours.
  bool allows(NotificationKind kind, DateTime at) =>
      kind.isCritical || !inQuietHours(at);

  /// The text actually posted: neutral when sensitive content is hidden.
  NotificationText textFor(String title, String body) => hideSensitive
      ? neutralNotificationText
      : NotificationText(title: title, body: body);

  /// Action labels; neutral variants never name SOS or cravings.
  String label(String sensitive, String neutral) =>
      hideSensitive ? neutral : sensitive;

  Map<String, Object> toJson() => {
    'quietHoursEnabled': quietHoursEnabled,
    'quietHours': quietHours.toJson(),
    'hideSensitiveNotifications': hideSensitive,
  };

  /// Reads the keys from a persisted state map; malformed values fall back.
  factory NotificationPrefs.fromState(Map<String, dynamic> map) {
    final window = map['quietHours'];
    RiskWindow? parsed;
    try {
      parsed = window is Map ? RiskWindow.fromJson(window) : null;
    } catch (_) {
      parsed = null;
    }
    final valid =
        parsed != null &&
        parsed.startMinutes != parsed.endMinutes &&
        window is Map &&
        window['startMinutes'] == parsed.startMinutes &&
        window['endMinutes'] == parsed.endMinutes;
    return NotificationPrefs(
      quietHoursEnabled: map['quietHoursEnabled'] == true,
      quietHours: valid ? parsed : defaultQuietHours,
      // Privacy flag: anything but an explicit false keeps content hidden
      // once the key exists.
      hideSensitive: map.containsKey('hideSensitiveNotifications')
          ? map['hideSensitiveNotifications'] != false
          : false,
    );
  }
}

/// Prefs for background isolates that only have the raw state file. An
/// unreadable file fails private: content hidden, no quiet hours.
NotificationPrefs notificationPrefsFromRawState(String? rawState) {
  try {
    final decoded = rawState == null ? null : jsonDecode(rawState);
    if (decoded is Map) {
      return NotificationPrefs.fromState(decoded.cast<String, dynamic>());
    }
  } catch (_) {
    /* Fall through to the private default. */
  }
  return const NotificationPrefs(hideSensitive: true);
}
