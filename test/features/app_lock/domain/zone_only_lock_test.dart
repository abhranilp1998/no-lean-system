import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/app_lock/domain/locked_app.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';

void main() {
  const app = LockedApp(packageName: 'com.example.pay', label: 'Pay');
  const window = RiskWindow.defaultWindow();

  test('schedule off still locks inside a danger zone', () {
    final p = AppLockPolicy.fromJson({
      'enabled': true,
      'apps': [app.toJson()],
      'schedule': 'off',
      'lockInsideDangerZones': false, // old state that locked nothing
    });
    expect(p.lockInsideDangerZones, isTrue);
    expect(p.armed, isTrue);
    final at = DateTime(2026, 11, 4, 12);
    expect(
      p.isActiveAt(at, riskWindow: window, insideDangerZone: true),
      isTrue,
    );
    expect(p.isActiveAt(at, riskWindow: window), isFalse);
  });

  test('other schedules keep the zone toggle as chosen', () {
    final p = const AppLockPolicy(
      enabled: true,
      apps: [app],
      schedule: AppLockSchedule.always,
      lockInsideDangerZones: false,
    ).sanitized();
    expect(p.lockInsideDangerZones, isFalse);
  });
}
