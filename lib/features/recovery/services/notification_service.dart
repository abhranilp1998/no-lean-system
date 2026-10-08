import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/theme/app_theme.dart';
import '../domain/notification_policy.dart';
import '../domain/risk_alert_plan.dart';
import '../domain/risk_window.dart';

/// Monochrome status-bar icon (`res/drawable/ic_stat_no_lean.xml`). Android
/// draws small icons from alpha only, and the name is resolved at runtime, so
/// `res/raw/keep.xml` must keep it from the release resource shrinker.
const notificationSmallIcon = 'ic_stat_no_lean';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionRequested = false;

  /// Quiet hours and lock-screen privacy. The controller keeps this in sync;
  /// background isolates pass prefs read from the state file instead.
  NotificationPrefs prefs = const NotificationPrefs();

  final _actionStreamController = StreamController<String>.broadcast();
  Stream<String> get actionStream => _actionStreamController.stream;

  /// Simulates a tapped notification action in tests.
  @visibleForTesting
  void debugEmitAction(String actionId) =>
      _actionStreamController.add(actionId);

  Future<void> _initialize({required bool requestPermission}) async {
    if (!_initialized) {
      try {
        final zone = await const MethodChannel(
          'no_lean/timezone',
        ).invokeMethod<String>('get');
        if (zone != null) {
          tz.setLocalLocation(tz.getLocation(zone));
        }
      } catch (_) {
        // UTC is the safe fallback if a platform does not expose its IANA zone.
      }

      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings(notificationSmallIcon),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.actionId != null) {
            _actionStreamController.add(response.actionId!);
          }
        },
      );
      _initialized = true;
    }

    if (requestPermission && !_permissionRequested) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
      _permissionRequested = true;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Whether Android currently allows exact alarms for this app.
  Future<bool> exactAlarmsAllowed() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "Alarms & reminders" grant. Returns the new state.
  Future<bool> requestExactAlarms() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {
      /* Older Android versions grant exact alarms implicitly. */
    }
    return exactAlarmsAllowed();
  }

  Future<void> scheduleRiskWindow(
    List<RiskAlert> alerts, {
    required RiskWindow riskWindow,
  }) async {
    try {
      await _initialize(requestPermission: true);
      await _cancelScheduled();
      if (alerts.isEmpty) return;

      var exactAllowed = await exactAlarmsAllowed();
      for (final alert in alerts) {
        final hour = alert.minuteOfDay ~/ 60;
        final minute = alert.minuteOfDay % 60;
        final now = tz.TZDateTime.now(tz.local);
        var scheduled = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        );
        if (!scheduled.isAfter(now)) {
          scheduled = scheduled.add(const Duration(days: 1));
        }
        // Risk-window alerts are critical: quiet hours never mute them.
        final text = prefs.textFor(alert.title, alert.body);
        final mode = await scheduleWithExactFallback(
          exactAllowed: exactAllowed,
          schedule: (mode) => _plugin.zonedSchedule(
            alert.id,
            text.title,
            text.body,
            scheduled,
            _details(alert, riskWindow, text),
            androidScheduleMode: mode,
            matchDateTimeComponents: DateTimeComponents.time,
          ),
        );
        exactAllowed = mode == AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (_) {
      // Notification support must never prevent local recovery tracking.
    }
  }

  NotificationDetails _details(
    RiskAlert alert,
    RiskWindow riskWindow,
    NotificationText text,
  ) => NotificationDetails(
    android: AndroidNotificationDetails(
      'risk_window_v2',
      'NO LEAN risk window',
      channelDescription:
          'High-visibility recovery interrupts during your configured risk window',
      importance: Importance.max,
      priority: Priority.high,
      color: red,
      colorized: !prefs.hideSensitive,
      enableLights: true,
      ledColor: cyan,
      enableVibration: true,
      playSound: true,
      visibility: lockScreenVisibility,
      category: AndroidNotificationCategory.reminder,
      ticker: neutralNotificationText.title,
      subText: prefs.hideSensitive ? null : riskWindow.label,
      styleInformation: BigTextStyleInformation(
        text.body,
        contentTitle: text.title,
      ),
      actions: [
        AndroidNotificationAction(
          'action_sos',
          prefs.label('OPEN SOS', 'OPEN'),
          showsUserInterface: true,
          cancelNotification: true,
        ),
        if (alert.kind == RiskAlertKind.preWindow)
          AndroidNotificationAction(
            'action_code',
            prefs.label('CODE INSTEAD', 'START TASK'),
            showsUserInterface: true,
            cancelNotification: true,
          )
        else
          AndroidNotificationAction(
            'action_safe',
            prefs.label('I\'M SAFE', 'OK'),
            showsUserInterface: true,
            cancelNotification: true,
          ),
        AndroidNotificationAction(
          'action_crave',
          prefs.label('LOG CRAVING', 'LOG'),
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    ),
  );

  /// Every notification is VISIBILITY_PRIVATE: on lock screens set to hide
  /// sensitive content, Android shows its own neutral public version (app
  /// name + "Contents hidden"). flutter_local_notifications 19.5 cannot set a
  /// custom publicVersion, so "hide sensitive content" additionally makes the
  /// posted title, body and action labels neutral everywhere.
  static const lockScreenVisibility = NotificationVisibility.private;

  bool _launchActionTaken = false;

  /// The action button that cold-started the app, if any. Android does not
  /// deliver it through the response callback when the process was dead
  /// (e.g. OPEN SOS on a background danger-zone alert). Returned once.
  Future<String?> takeLaunchAction() async {
    if (_launchActionTaken) return null;
    _launchActionTaken = true;
    try {
      await _initialize(requestPermission: false);
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        return details?.notificationResponse?.actionId;
      }
    } catch (_) {
      // No launch details on this platform.
    }
    return null;
  }

  static const zoneAlertId = 600;

  /// Loud danger-zone notification. Requests a full-screen intent; Android
  /// only honours it where the app may use full-screen intents (and shows a
  /// heads-up notification otherwise). "I'M LEAVING" dismisses in one tap.
  Future<void> showZoneAlert({
    required String title,
    required String body,
    NotificationPrefs? prefs,
  }) async {
    // Zone alerts are critical: quiet hours never mute them.
    final policy = prefs ?? this.prefs;
    final text = policy.textFor(title, body);
    try {
      await _initialize(requestPermission: false);
      await _plugin.show(
        zoneAlertId,
        text.title,
        text.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'danger_zone_v1',
            'NO LEAN danger zones',
            channelDescription:
                'Interrupts when you enter a place you marked as a danger zone',
            importance: Importance.max,
            priority: Priority.max,
            color: red,
            colorized: !policy.hideSensitive,
            enableVibration: true,
            playSound: true,
            fullScreenIntent: true,
            visibility: lockScreenVisibility,
            category: AndroidNotificationCategory.reminder,
            ticker: neutralNotificationText.title,
            styleInformation: BigTextStyleInformation(
              text.body,
              contentTitle: text.title,
            ),
            actions: [
              AndroidNotificationAction(
                'action_sos',
                policy.label('OPEN SOS', 'OPEN'),
                showsUserInterface: true,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                'action_crave',
                policy.label('LOG CRAVING', 'LOG'),
                showsUserInterface: true,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                'action_zone_exit',
                policy.label('I\'M LEAVING', 'DISMISS'),
                cancelNotification: true,
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // A missing notification must never break location handling.
    }
  }

  static const codeTimerId = 700;

  /// Non-critical: tells the user a Code Instead block ended while the app
  /// was in the background. Skipped entirely when it would land in quiet
  /// hours. Returns whether it was scheduled.
  Future<bool> scheduleCodeTimer({
    required DateTime endsAt,
    required String task,
  }) async {
    if (!prefs.allows(NotificationKind.codeTimer, endsAt)) {
      await cancelCodeTimer();
      return false;
    }
    final text = prefs.textFor(
      'CODE BLOCK DONE',
      'Time is up on: $task Log how it went, or start another block.',
    );
    try {
      await _initialize(requestPermission: true);
      final when = tz.TZDateTime.from(endsAt, tz.local);
      await scheduleWithExactFallback(
        exactAllowed: await exactAlarmsAllowed(),
        schedule: (mode) => _plugin.zonedSchedule(
          codeTimerId,
          text.title,
          text.body,
          when,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'code_timer_v1',
              'NO LEAN focus timer',
              channelDescription: 'Tells you when a Code Instead block ends',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              visibility: lockScreenVisibility,
              category: AndroidNotificationCategory.reminder,
              ticker: neutralNotificationText.title,
            ),
          ),
          androidScheduleMode: mode,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelCodeTimer() async {
    try {
      await _plugin.cancel(codeTimerId);
    } catch (_) {
      // Optional on tests and unsupported platforms.
    }
  }

  Future<void> cancelRiskWindow() async {
    try {
      // Cancellation does not require permission and Android can service it
      // without initializing the notification callback pipeline first.
      await _cancelScheduled();
    } catch (_) {
      // Notifications are optional on tests and unsupported platforms.
    }
  }

  Future<void> _cancelScheduled() async {
    for (var id = riskAlertFirstId; id <= riskAlertLastId; id++) {
      await _plugin.cancel(id);
    }
  }
}

/// Schedules with exact alarms when Android allows them and falls back to
/// inexact delivery when they are unavailable or revoked mid-schedule.
/// Returns the mode that was actually used.
Future<AndroidScheduleMode> scheduleWithExactFallback({
  required bool exactAllowed,
  required Future<void> Function(AndroidScheduleMode mode) schedule,
}) async {
  if (exactAllowed) {
    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
      return AndroidScheduleMode.exactAllowWhileIdle;
    } on PlatformException catch (error) {
      if (error.code != 'exact_alarms_not_permitted') rethrow;
    }
  }
  await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
  return AndroidScheduleMode.inexactAllowWhileIdle;
}
