import 'package:flutter/services.dart';

class HomeWidgetService {
  const HomeWidgetService._();

  static Future<void> update({
    required DateTime lastDose,
    required String cleanTime,
    required int streak,
    required bool isRiskWindow,
    required bool hasPledgedToday,
  }) async {
    try {
      await const MethodChannel(
        'no_lean/widget',
      ).invokeMethod<void>('update', <String, Object>{
        'lastDoseEpochMillis': lastDose.millisecondsSinceEpoch,
        'cleanTime': cleanTime,
        'streak': '$streak DAYS',
        'isRiskWindow': isRiskWindow,
        'hasPledgedToday': hasPledgedToday,
      });
    } catch (_) {
      // Widget support is optional on unsupported launchers; core tracking stays local.
    }
  }
}
