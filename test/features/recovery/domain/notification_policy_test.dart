import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';

void main() {
  const overnight = NotificationPrefs(
    quietHoursEnabled: true,
    quietHours: RiskWindow(startMinutes: 22 * 60, endMinutes: 7 * 60),
  );

  test('only risk-window and danger-zone alerts are critical', () {
    expect(NotificationKind.riskWindow.isCritical, isTrue);
    expect(NotificationKind.dangerZone.isCritical, isTrue);
    expect(NotificationKind.codeTimer.isCritical, isFalse);
  });

  test('quiet hours mute non-critical kinds only, across midnight', () {
    final lateNight = DateTime(2026, 10, 9, 23, 30);
    final earlyMorning = DateTime(2026, 10, 10, 6, 59);
    final afternoon = DateTime(2026, 10, 10, 15);
    for (final at in [lateNight, earlyMorning]) {
      expect(overnight.allows(NotificationKind.codeTimer, at), isFalse);
      expect(overnight.allows(NotificationKind.riskWindow, at), isTrue);
      expect(overnight.allows(NotificationKind.dangerZone, at), isTrue);
    }
    expect(overnight.allows(NotificationKind.codeTimer, afternoon), isTrue);
  });

  test('quiet hours switched off allow everything', () {
    const off = NotificationPrefs(
      quietHours: RiskWindow(startMinutes: 0, endMinutes: 23 * 60 + 59),
    );
    expect(
      off.allows(NotificationKind.codeTimer, DateTime(2026, 10, 9, 12)),
      isTrue,
    );
  });

  test('hide sensitive swaps titles, bodies and labels for neutral copy', () {
    const hidden = NotificationPrefs(hideSensitive: true);
    final text = hidden.textFor('RISK WINDOW OPEN', 'Day 12 clean. Hold it.');
    expect(text.title, neutralNotificationText.title);
    expect(text.body, neutralNotificationText.body);
    expect(hidden.label('LOG CRAVING', 'LOG'), 'LOG');
    for (final word in ['RISK', 'clean', 'craving', 'relapse', 'zone']) {
      expect(
        '${text.title} ${text.body}'.toLowerCase(),
        isNot(contains(word.toLowerCase())),
      );
    }

    const shown = NotificationPrefs();
    expect(shown.textFor('A', 'B').title, 'A');
    expect(shown.label('LOG CRAVING', 'LOG'), 'LOG CRAVING');
  });

  test('prefs round-trip through state JSON', () {
    const prefs = NotificationPrefs(
      quietHoursEnabled: true,
      quietHours: RiskWindow(startMinutes: 60, endMinutes: 300),
      hideSensitive: true,
    );
    final back = NotificationPrefs.fromState(
      jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>,
    );
    expect(back.quietHoursEnabled, isTrue);
    expect(back.quietHours.startMinutes, 60);
    expect(back.quietHours.endMinutes, 300);
    expect(back.hideSensitive, isTrue);
  });

  test('background isolates fail private on an unreadable state file', () {
    expect(notificationPrefsFromRawState(null).hideSensitive, isTrue);
    expect(notificationPrefsFromRawState('{oops').hideSensitive, isTrue);
    expect(notificationPrefsFromRawState('{}').hideSensitive, isFalse);
    expect(
      notificationPrefsFromRawState(
        '{"hideSensitiveNotifications":true}',
      ).hideSensitive,
      isTrue,
    );
  });
}
