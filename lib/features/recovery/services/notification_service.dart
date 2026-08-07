import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/theme/app_theme.dart';

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

  Future<void> scheduleRiskWindow(List<String> messages) async {
    await _initialize();
    try {
      await cancelRiskWindow();
      if (messages.isEmpty) return;

      const moments = [17 * 60 + 30, 18 * 60 + 15, 19 * 60, 19 * 60 + 45];
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
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'risk_window',
              'Risk window',
              channelDescription:
                  'Direct NO LEAN interrupts from 17:30 to 20:00',
              importance: Importance.max,
              priority: Priority.high,
              color: red,
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
    for (var id = 500; id < 504; id++) {
      await _plugin.cancel(id);
    }
  }
}
