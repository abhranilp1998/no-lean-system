import 'package:flutter/services.dart';

class HomeWidgetService {
  const HomeWidgetService._();

  static Future<void> update({
    required String cleanTime,
    required int streak,
  }) async {
    try {
      await const MethodChannel('no_lean/widget').invokeMethod<void>(
        'update',
        <String, String>{'cleanTime': cleanTime, 'streak': '$streak DAYS'},
      );
    } catch (_) {
      // Widget support is optional on unsupported launchers; core tracking stays local.
    }
  }
}
