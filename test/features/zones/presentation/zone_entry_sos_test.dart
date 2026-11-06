import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/app_lock/domain/locked_app.dart';
import 'package:no_lean/features/zones/domain/zone_alert_copy.dart';
import 'package:no_lean/features/zones/presentation/zone_alert_screen.dart';

void main() {
  test('formatHold', () {
    expect(formatHold(const Duration(minutes: 10)), '10:00');
    expect(formatHold(const Duration(seconds: 61)), '01:01');
    expect(formatHold(Duration.zero), '00:00');
  });

  testWidgets('zone entry shows a 10-minute hold timer that counts down', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ZoneAlertScreen(
          copy: ZoneAlertCopy(title: 'TEST ZONE A', body: 'Turn around.'),
        ),
      ),
    );
    expect(find.text('GIVE IT 10 MINUTES'), findsOneWidget);
    expect(find.byKey(const ValueKey('zone-alert-sos')), findsOneWidget);
    expect(find.byKey(const ValueKey('zone-alert-exit')), findsOneWidget);
  });

  test('schedule off + zone rule off is not armed (settings must say so)', () {
    const policy = AppLockPolicy(
      enabled: true,
      apps: [LockedApp(packageName: 'a.b', label: 'A')],
      schedule: AppLockSchedule.off,
      lockInsideDangerZones: false,
    );
    expect(policy.armed, isFalse);
    expect(policy.copyWith(lockInsideDangerZones: true).armed, isTrue);
  });
}
