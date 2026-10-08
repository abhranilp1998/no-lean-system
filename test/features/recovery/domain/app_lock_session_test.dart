import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/app_lock_session.dart';

void main() {
  final t0 = DateTime(2026, 10, 8, 17, 5);

  AppLockReason? resolve(
    AppLockSession session, {
    bool relock = false,
    bool armed = true,
    bool inWindow = true,
  }) => session.resolve(
    relockPending: relock,
    riskWindowWallArmed: armed,
    inRiskWindow: inWindow,
  );

  test('locks inside an armed risk window until unlocked', () {
    final session = AppLockSession();
    expect(resolve(session), AppLockReason.riskWindow);
    session.onUnlocked();
    expect(resolve(session), isNull);
  });

  test('never locks outside the window or when the wall is not armed', () {
    final session = AppLockSession();
    expect(resolve(session, inWindow: false), isNull);
    expect(resolve(session, armed: false), isNull);
  });

  test('post-relapse relock wins regardless of window or prior unlock', () {
    final session = AppLockSession()..onUnlocked();
    expect(
      resolve(session, relock: true, armed: false, inWindow: false),
      AppLockReason.relapseLogged,
    );
    expect(resolve(session, relock: true), AppLockReason.relapseLogged);
  });

  test('a short trip to a system dialog keeps the unlock', () {
    final session = AppLockSession()..onUnlocked();
    session.onBackgrounded(t0);
    session.onResumed(t0.add(const Duration(seconds: 10)));
    expect(resolve(session), isNull);
  });

  test('returning after the background grace locks the window again', () {
    final session = AppLockSession()..onUnlocked();
    session.onBackgrounded(t0);
    session.onResumed(t0.add(const Duration(seconds: 30)));
    expect(resolve(session), AppLockReason.riskWindow);
  });

  test('leaving the window forgets the unlock for the next occurrence', () {
    final session = AppLockSession()..onUnlocked();
    expect(resolve(session), isNull);
    expect(resolve(session, inWindow: false), isNull);
    expect(resolve(session), AppLockReason.riskWindow);
  });
}
