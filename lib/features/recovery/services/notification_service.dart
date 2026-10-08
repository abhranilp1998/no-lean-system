import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/theme/app_theme.dart';
import '../domain/risk_alert_plan.dart';
import '../domain/risk_window.dart';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionRequested = false;

  final _actionStreamController = StreamController<String>.broadcast();
  Stream<String> get actionStream => _actionStreamController.stream;

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
          android: AndroidInitializationSettings('no_lean_icon'),
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
        final mode = await scheduleWithExactFallback(
          exactAllowed: exactAllowed,
          schedule: (mode) => _plugin.zonedSchedule(
            alert.id,
            alert.title,
            alert.body,
            scheduled,
            _details(alert, riskWindow),
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
  ) => NotificationDetails(
    android: AndroidNotificationDetails(
      'risk_window_v2',
      'NO LEAN risk window',
      channelDescription:
          'High-visibility recovery interrupts during your configured risk window',
      importance: Importance.max,
      priority: Priority.high,
      color: red,
      colorized: true,
      enableLights: true,
      ledColor: cyan,
      enableVibration: true,
      playSound: true,
      // PRIVATE: when the lock screen hides sensitive content, Android
      // shows only the app name and "Contents hidden". The plugin does not
      // expose a custom public version, so the ticker stays neutral too.
      visibility: NotificationVisibility.private,
      category: AndroidNotificationCategory.reminder,
      ticker: 'Scheduled check-in',
      subText: riskWindow.label,
      styleInformation: BigTextStyleInformation(
        alert.body,
        contentTitle: alert.title,
      ),
      actions: const [
        AndroidNotificationAction(
          'action_sos',
          'OPEN SOS',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'action_safe',
          'I\'M SAFE',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'action_crave',
          'LOG CRAVING',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    ),
  );

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
