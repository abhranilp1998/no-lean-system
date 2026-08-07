import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/theme/app_theme.dart';
import '../domain/risk_window.dart';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;
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
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> scheduleRiskWindow(
    List<String> messages, {
    required RiskWindow riskWindow,
  }) async {
    try {
      await _initialize();
      await _cancelScheduled();
      if (messages.isEmpty) return;

      final moments = riskWindow.reminderMinutes();
      for (var index = 0; index < moments.length; index++) {
        final message = messages[index % messages.length];
        final hour = moments[index] ~/ 60;
        final minute = moments[index] % 60;
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
        await _plugin.zonedSchedule(
          500 + index,
          'NO LEAN / RISK WINDOW',
          message,
          scheduled,
          NotificationDetails(
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
              visibility: NotificationVisibility.public,
              category: AndroidNotificationCategory.reminder,
              ticker: 'NO LEAN // HOLD THE LINE',
              subText: '${riskWindow.label} // PERSONAL OVERRIDE',
              styleInformation: BigTextStyleInformation(
                message,
                contentTitle: 'NO LEAN // RISK WINDOW',
                summaryText: 'STAY MOVING. DO NOT BUY.',
              ),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (_) {
      // Notification support must never prevent local recovery tracking.
    }
  }

  Future<void> cancelRiskWindow() async {
    try {
      await _initialize();
      await _cancelScheduled();
    } catch (_) {
      // Notifications are optional on tests and unsupported platforms.
    }
  }

  Future<void> _cancelScheduled() async {
    for (var id = 500; id < 504; id++) {
      await _plugin.cancel(id);
    }
  }
}
