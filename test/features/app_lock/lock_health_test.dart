import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/app_lock/presentation/app_lock_banner.dart';
import 'package:no_lean/features/app_lock/services/app_lock_gateway.dart';

void main() {
  final now = DateTime(2026, 11, 4, 22);
  AppLockStatus status({
    bool usage = true,
    bool overlay = true,
    bool running = true,
    DateTime? beat,
  }) => AppLockStatus(
    supported: true,
    usageAccess: usage,
    overlay: overlay,
    serviceRunning: running,
    heartbeatAt: beat,
  );

  group('AppLockStatus heartbeat (P0-1)', () {
    test('parses heartbeat and stop reason; older builds have none', () {
      final parsed = AppLockStatus.fromMap({
        'usageAccess': true,
        'overlay': true,
        'serviceRunning': true,
        'heartbeatAt': now.millisecondsSinceEpoch,
        'stopReason': 'usage_access',
      });
      expect(parsed.heartbeatAt, now);
      expect(parsed.stopReason, 'usage_access');
      final old = AppLockStatus.fromMap({'usageAccess': true});
      expect(old.heartbeatAt, isNull);
      expect(old.heartbeatStale(now), isFalse);
    });

    test('stale after two minutes without a poll', () {
      expect(
        status(
          beat: now.subtract(const Duration(seconds: 90)),
        ).heartbeatStale(now),
        isFalse,
      );
      expect(
        status(
          beat: now.subtract(const Duration(minutes: 3)),
        ).heartbeatStale(now),
        isTrue,
      );
    });

    test('banner reports a stale lock', () {
      final message = appLockHealthMessage(
        armed: true,
        status: status(beat: now.subtract(const Duration(minutes: 5))),
        now: now,
      );
      expect(message, contains('NOT RESPONDING'));
    });
  });

  group('shieldStateFor', () {
    ShieldState state(
      AppLockStatus? s, {
      bool enabled = true,
      bool armed = true,
    }) => shieldStateFor(enabled: enabled, armed: armed, status: s, now: now);

    test(
      'on when healthy',
      () => expect(state(status(beat: now)), ShieldState.on),
    );
    test(
      'not set up when disabled',
      () => expect(state(status(), enabled: false), ShieldState.notSetUp),
    );
    test(
      'off when usage access lost',
      () => expect(state(status(usage: false)), ShieldState.off),
    );
    test(
      'off when service stopped',
      () => expect(state(status(running: false)), ShieldState.off),
    );
    test(
      'off when heartbeat stale',
      () => expect(
        state(status(beat: now.subtract(const Duration(minutes: 10)))),
        ShieldState.off,
      ),
    );
    test(
      'limited when overlay lost',
      () => expect(state(status(overlay: false)), ShieldState.limited),
    );
  });
}
