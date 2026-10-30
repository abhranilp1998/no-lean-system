import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/home_widget_payload.dart';
import '../domain/risk_window.dart';

/// Pushes state to every NO LEAN home-screen widget size (2x1, 4x2, 4x3).
class HomeWidgetService {
  const HomeWidgetService._();

  @visibleForTesting
  static const channel = MethodChannel('no_lean/widget');

  static Future<void> update({
    required DateTime lastDose,
    required String cleanTime,
    required int streak,
    required bool isRiskWindow,
    required bool hasPledgedToday,
    bool privacy = false,
    RiskWindow? riskWindow,
  }) async {
    try {
      await channel.invokeMethod<void>(
        'update',
        homeWidgetPayload(
          lastDose: lastDose,
          cleanTime: cleanTime,
          streak: streak,
          isRiskWindow: isRiskWindow,
          hasPledgedToday: hasPledgedToday,
          privacy: privacy,
          riskStartMinutes: riskWindow?.startMinutes,
          riskEndMinutes: riskWindow?.endMinutes,
        ),
      );
    } catch (_) {
      // Widget support is optional on unsupported launchers; core tracking stays local.
    }
  }
}
