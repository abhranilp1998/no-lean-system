import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/services/feedback_preferences.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/effect_intensity.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/relapse_lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'relapse lock rejects an invalid PIN without resetting clean time',
    () async {
      final lock = _FakeRelapseLockGateway();
      final controller = RecoveryController(relapseLock: lock)
        ..lastDose = DateTime.now().subtract(const Duration(days: 5));
      await controller.enableRelapseLock('2468');
      final before = controller.lastDose;

      final result = await controller.recordRelapse(
        pin: '1111',
        tryBiometrics: false,
      );

      expect(result, ProtectedActionResult.denied);
      expect(controller.lastDose, before);
      expect(controller.streak, greaterThanOrEqualTo(4));
    },
  );

  test('relapse lock accepts the encrypted PIN fallback', () async {
    final lock = _FakeRelapseLockGateway();
    final controller = RecoveryController(relapseLock: lock)
      ..lastDose = DateTime.now().subtract(const Duration(days: 5));
    await controller.enableRelapseLock('2468');

    final result = await controller.recordRelapse(
      pin: '2468',
      tryBiometrics: false,
    );

    expect(result, ProtectedActionResult.completed);
    expect(controller.streak, 0);
  });

  test('relapse lock accepts a successful biometric challenge', () async {
    final lock = _FakeRelapseLockGateway()
      ..biometricResult = BiometricAuthResult.authenticated;
    final controller = RecoveryController(relapseLock: lock)
      ..lastDose = DateTime.now().subtract(const Duration(days: 2));
    await controller.enableRelapseLock('2468');

    final result = await controller.recordRelapse();

    expect(result, ProtectedActionResult.completed);
    expect(lock.biometricRequests, 1);
    expect(controller.streak, 0);
  });

  test('disabling the lock also requires authentication', () async {
    final lock = _FakeRelapseLockGateway();
    final controller = RecoveryController(relapseLock: lock);
    await controller.enableRelapseLock('2468');

    final unauthenticated = await controller.disableRelapseLock();
    final authenticated = await controller.disableRelapseLock(
      pin: '2468',
      tryBiometrics: false,
    );

    expect(unauthenticated, ProtectedActionResult.authenticationRequired);
    expect(authenticated, ProtectedActionResult.completed);
    expect(controller.requirePinAfterRelapse, isFalse);
    expect(lock.storedPin, isNull);
  });

  test('version 3 plaintext PIN migrates into secure storage', () async {
    SharedPreferences.setMockInitialValues({
      'recovery_state': jsonEncode({
        'stateVersion': 3,
        'lastDose': DateTime(2026, 8, 1).toIso8601String(),
        'requirePinAfterRelapse': true,
        'riskReminders': false,
        'pin': '2468',
      }),
    });
    final lock = _FakeRelapseLockGateway();
    final controller = RecoveryController(relapseLock: lock);

    await controller.load();

    final preferences = await SharedPreferences.getInstance();
    final migratedState =
        jsonDecode(preferences.getString('recovery_state')!)
            as Map<String, dynamic>;
    expect(lock.storedPin, '2468');
    expect(controller.requirePinAfterRelapse, isTrue);
    expect(migratedState['stateVersion'], RecoveryController.stateVersion);
    expect(migratedState.containsKey('pin'), isFalse);
  });

  test('version 4 settings migrate and feedback preferences persist', () async {
    SharedPreferences.setMockInitialValues({
      'recovery_state': jsonEncode({
        'stateVersion': 4,
        'lastDose': DateTime(2026, 8, 1).toIso8601String(),
        'riskReminders': false,
        'soundscape': true,
        'intensity': 'aggressive',
      }),
    });
    final controller = RecoveryController(
      relapseLock: _FakeRelapseLockGateway(),
    );

    await controller.load();

    expect(controller.soundscape, isTrue);
    expect(controller.hapticFeedback, isTrue);
    expect(controller.feedbackSound, FeedbackSoundEffect.neonPulse);

    await controller.updateFeedbackPreferences(
      soundEnabled: true,
      vibrationEnabled: false,
      soundEffect: FeedbackSoundEffect.reactorPing,
    );
    await controller.setSetting('intensity', EffectIntensity.ultra);

    final preferences = await SharedPreferences.getInstance();
    final migratedState =
        jsonDecode(preferences.getString('recovery_state')!)
            as Map<String, dynamic>;
    expect(migratedState['stateVersion'], 6);
    expect(migratedState['soundscape'], isTrue);
    expect(migratedState['hapticFeedback'], isFalse);
    expect(migratedState['feedbackSound'], 'reactorPing');
    expect(migratedState['intensity'], 'ultra');
  });

  test('relapseCooldownUntil and cooldownMinutes persist to storage', () async {
    SharedPreferences.setMockInitialValues({
      'recovery_state': jsonEncode({
        'stateVersion': RecoveryController.stateVersion,
        'events': [],
        'relapseCooldownUntil': DateTime(2026, 8, 1).toIso8601String(),
      }),
    });
    final controller = RecoveryController(
      relapseLock: _FakeRelapseLockGateway(),
    );

    await controller.load();
    expect(controller.relapseCooldownUntil, DateTime(2026, 8, 1));

    controller.relapseCooldownUntil = DateTime(2026, 8, 2);
    await controller.appendEvent(RecoveryEvent.create(type: RecoveryEventType.settingsChange)); // trigger save

    final preferences = await SharedPreferences.getInstance();
    final migratedState =
        jsonDecode(preferences.getString('recovery_state')!)
            as Map<String, dynamic>;
    
    expect(migratedState['relapseCooldownUntil'], DateTime(2026, 8, 2).toIso8601String());
  });
}

class _FakeRelapseLockGateway implements RelapseLockGateway {
  String? storedPin;
  BiometricAuthResult biometricResult = BiometricAuthResult.unavailable;
  int biometricRequests = 0;

  @override
  Future<BiometricAuthResult> authenticateBiometrically({
    required String reason,
  }) async {
    biometricRequests++;
    return biometricResult;
  }

  @override
  Future<void> clearPin() async => storedPin = null;

  @override
  Future<bool> hasPin() async => storedPin != null;

  @override
  Future<void> savePin(String pin) async => storedPin = pin;

  @override
  Future<bool> verifyPin(String pin) async => storedPin == pin;
}
