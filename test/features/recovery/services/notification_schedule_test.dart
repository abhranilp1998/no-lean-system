import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';

void main() {
  test('uses exact alarms when Android allows them', () async {
    final modes = <AndroidScheduleMode>[];
    final used = await scheduleWithExactFallback(
      exactAllowed: true,
      schedule: (mode) async => modes.add(mode),
    );
    expect(used, AndroidScheduleMode.exactAllowWhileIdle);
    expect(modes, [AndroidScheduleMode.exactAllowWhileIdle]);
  });

  test('goes straight to inexact when exact alarms are not granted', () async {
    final modes = <AndroidScheduleMode>[];
    final used = await scheduleWithExactFallback(
      exactAllowed: false,
      schedule: (mode) async => modes.add(mode),
    );
    expect(used, AndroidScheduleMode.inexactAllowWhileIdle);
    expect(modes, [AndroidScheduleMode.inexactAllowWhileIdle]);
  });

  test('falls back to inexact if the grant is revoked mid-schedule', () async {
    final modes = <AndroidScheduleMode>[];
    final used = await scheduleWithExactFallback(
      exactAllowed: true,
      schedule: (mode) async {
        modes.add(mode);
        if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
          throw PlatformException(code: 'exact_alarms_not_permitted');
        }
      },
    );
    expect(used, AndroidScheduleMode.inexactAllowWhileIdle);
    expect(modes, [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ]);
  });

  test('other platform errors are not swallowed by the fallback', () async {
    await expectLater(
      scheduleWithExactFallback(
        exactAllowed: true,
        schedule: (_) async => throw PlatformException(code: 'other'),
      ),
      throwsA(isA<PlatformException>()),
    );
  });
}
