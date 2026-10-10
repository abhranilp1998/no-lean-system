import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(
    () => NotificationService.instance.prefs = const NotificationPrefs(),
  );

  test('a code timer ending in quiet hours is never scheduled', () async {
    NotificationService.instance.prefs = const NotificationPrefs(
      quietHoursEnabled: true,
      quietHours: RiskWindow(startMinutes: 22 * 60, endMinutes: 7 * 60),
    );
    final scheduled = await NotificationService.instance.scheduleCodeTimer(
      endsAt: DateTime(2026, 10, 9, 23, 15),
      task: 'x',
    );
    expect(scheduled, isFalse);
  });
}
