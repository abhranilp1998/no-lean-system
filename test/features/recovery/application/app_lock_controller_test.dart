import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(RecoveryController, MemoryRecoveryStore, FakeRelapseLock)> loaded({
    String? stored,
    DateTime Function()? now,
  }) async {
    final store = MemoryRecoveryStore(stored);
    final lock = FakeRelapseLock();
    final controller = RecoveryController(
      store: store,
      relapseLock: lock,
      now: now,
    );
    await controller.load();
    return (controller, store, lock);
  }

  test('v7 state migrates to v8 with safe lock defaults', () async {
    final v7 = jsonEncode({
      'stateVersion': 7,
      'events': [
        RecoveryEvent.create(
          type: RecoveryEventType.recoveryStart,
          timestamp: DateTime(2026, 9, 1),
        ).toJson(),
      ],
      'requirePinAfterRelapse': true,
    });
    final (controller, store, _) = await loaded(stored: v7);

    expect(controller.riskWindowLock, isTrue);
    expect(controller.appLockPending, isFalse);
    expect(controller.riskWindowWallArmed, isTrue);
    final saved = jsonDecode(store.value!) as Map;
    expect(saved['stateVersion'], 8);
    expect(saved['riskWindowLock'], isTrue);
    expect(saved['appLockPending'], isFalse);
    expect(store.copies.single, contains('"stateVersion":7'));
  });

  test('a malformed lock flag never silently disables protection', () async {
    final state = jsonEncode({
      'stateVersion': 8,
      'events': [
        RecoveryEvent.create(
          type: RecoveryEventType.recoveryStart,
          timestamp: DateTime(2026, 9, 1),
        ).toJson(),
      ],
      'requirePinAfterRelapse': true,
      'riskWindowLock': 'no',
      'appLockPending': 1,
    });
    final (controller, _, _) = await loaded(stored: state);

    expect(controller.riskWindowLock, isTrue);
    expect(controller.appLockPending, isTrue);
  });

  test('the wall is never armed without a PIN', () async {
    final (controller, _, _) = await loaded();
    expect(controller.riskWindowLock, isTrue);
    expect(controller.riskWindowWallArmed, isFalse);

    await controller.recordRelapse();
    expect(controller.relockPending, isFalse);
  });

  test('a saved relapse re-locks the app until authenticated', () async {
    final (controller, store, _) = await loaded();
    await controller.enableRelapseLock('2468');

    await controller.recordRelapse(pin: '2468', tryBiometrics: false);
    expect(controller.relockPending, isTrue);
    expect(jsonDecode(store.value!)['appLockPending'], isTrue);

    expect(
      await controller.unlockApp(pin: '0000', tryBiometrics: false),
      ProtectedActionResult.denied,
    );
    expect(controller.relockPending, isTrue);

    expect(
      await controller.unlockApp(tryBiometrics: false),
      ProtectedActionResult.authenticationRequired,
    );
    expect(
      await controller.unlockApp(pin: '2468', tryBiometrics: false),
      ProtectedActionResult.completed,
    );
    expect(controller.relockPending, isFalse);
    expect(jsonDecode(store.value!)['appLockPending'], isFalse);
  });

  test('a denied relapse save does not re-lock the app', () async {
    final (controller, _, _) = await loaded();
    await controller.enableRelapseLock('2468');

    await controller.recordRelapse(pin: '1111', tryBiometrics: false);
    expect(controller.relockPending, isFalse);
  });

  test('turning the wall off authenticates; turning it on does not', () async {
    final (controller, _, _) = await loaded();
    await controller.enableRelapseLock('2468');

    expect(
      await controller.setRiskWindowLock(false, tryBiometrics: false),
      ProtectedActionResult.authenticationRequired,
    );
    expect(controller.riskWindowLock, isTrue);
    expect(
      await controller.setRiskWindowLock(
        false,
        pin: '2468',
        tryBiometrics: false,
      ),
      ProtectedActionResult.completed,
    );
    expect(controller.riskWindowLock, isFalse);
    expect(controller.riskWindowWallArmed, isFalse);

    expect(
      await controller.setRiskWindowLock(true, tryBiometrics: false),
      ProtectedActionResult.completed,
    );
    expect(controller.riskWindowLock, isTrue);
  });

  test('setting a new PIN re-arms the wall by default', () async {
    final (controller, _, _) = await loaded();
    await controller.enableRelapseLock('2468');
    await controller.setRiskWindowLock(false, pin: '2468');
    await controller.disableRelapseLock(pin: '2468');
    expect(controller.riskWindowWallArmed, isFalse);

    await controller.enableRelapseLock('1357');
    expect(controller.riskWindowWallArmed, isTrue);
  });

  test('wall follows the configured window', () async {
    var now = DateTime(2026, 10, 8, 16, 59);
    final (controller, _, _) = await loaded(now: () => now);
    await controller.enableRelapseLock('2468');

    expect(controller.isRiskWindow, isFalse);
    now = DateTime(2026, 10, 8, 17);
    expect(controller.isRiskWindow, isTrue);
  });

  test('imported preferences cannot change lock state', () async {
    final (controller, _, _) = await loaded();
    await controller.enableRelapseLock('2468');

    await controller.mergeImportedEvents(
      const [],
      preferences: {'riskWindowLock': false, 'appLockPending': false},
      restorePreferences: true,
      pin: '2468',
      tryBiometrics: false,
    );

    expect(controller.riskWindowLock, isTrue);
  });
}
