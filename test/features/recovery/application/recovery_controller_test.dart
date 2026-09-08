import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/services/feedback_preferences.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/effect_intensity.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/domain/sos_session.dart';
import 'package:no_lean/features/recovery/services/relapse_lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'fresh install creates a neutral baseline and a zero-day streak',
    () async {
      final before = DateTime.now();
      final controller = RecoveryController(
        relapseLock: _FakeRelapseLockGateway(),
      );
      await controller.load();

      await controller.load();

      expect(controller.events, hasLength(1));
      expect(controller.events.single.type, RecoveryEventType.recoveryStart);
      expect(controller.lastDose.isBefore(before), isFalse);
      expect(controller.streak, 0);
      expect(controller.riskReminders, isFalse);
    },
  );

  test(
    'relapse lock rejects an invalid PIN without resetting clean time',
    () async {
      final lock = _FakeRelapseLockGateway();
      final controller = RecoveryController(relapseLock: lock);
      await controller.load();
      await controller.recordRelapse(
        occurredAt: [DateTime.now().subtract(const Duration(days: 5))],
      );
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
    final controller = RecoveryController(relapseLock: lock);
    await controller.load();
    await controller.recordRelapse(
      occurredAt: [DateTime.now().subtract(const Duration(days: 5))],
    );
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
    final controller = RecoveryController(relapseLock: lock);
    await controller.load();
    await controller.recordRelapse(
      occurredAt: [DateTime.now().subtract(const Duration(days: 2))],
    );
    await controller.enableRelapseLock('2468');

    final result = await controller.recordRelapse();

    expect(result, ProtectedActionResult.completed);
    expect(lock.biometricRequests, 1);
    expect(controller.streak, 0);
  });

  test('disabling the lock also requires authentication', () async {
    final lock = _FakeRelapseLockGateway();
    final controller = RecoveryController(relapseLock: lock);
    await controller.load();
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
    expect(migratedState['stateVersion'], RecoveryController.stateVersion);
    expect(migratedState['soundscape'], isTrue);
    expect(migratedState['hapticFeedback'], isFalse);
    expect(migratedState['feedbackSound'], 'reactorPing');
    expect(migratedState['intensity'], 'ultra');
  });

  test(
    'legacy lastDose migrates as baseline without inventing a relapse',
    () async {
      final baseline = DateTime.now().subtract(const Duration(days: 5));
      SharedPreferences.setMockInitialValues({
        'recovery_state': jsonEncode({
          'stateVersion': 5,
          'lastDose': baseline.toIso8601String(),
          'longestStreak': 31,
          'riskReminders': false,
        }),
      });
      final controller = RecoveryController(
        relapseLock: _FakeRelapseLockGateway(),
      );
      await controller.load();

      await controller.load();

      expect(controller.lastDose, baseline);
      expect(
        controller.events.where(
          (event) => event.type == RecoveryEventType.recoveryStart,
        ),
        hasLength(1),
      );
      expect(
        controller.events.where(
          (event) => event.type == RecoveryEventType.relapse,
        ),
        isEmpty,
      );
      expect(controller.longestStreak, 31);
    },
  );

  test('relapseCooldownUntil and cooldownMinutes persist to storage', () async {
    SharedPreferences.setMockInitialValues({
      'recovery_state': jsonEncode({
        'stateVersion': RecoveryController.stateVersion,
        'events': [],
        'relapseCooldownUntil': DateTime(2026, 8, 1).toIso8601String(),
        'cooldownMinutes': 30,
      }),
    });
    final controller = RecoveryController(
      relapseLock: _FakeRelapseLockGateway(),
    );
    await controller.load();

    await controller.load();
    expect(controller.relapseCooldownUntil, DateTime(2026, 8, 1));
    expect(controller.cooldownMinutes, 30);

    controller.relapseCooldownUntil = DateTime(2026, 8, 2);
    await controller.updateCooldownMinutes(20);

    final preferences = await SharedPreferences.getInstance();
    final migratedState =
        jsonDecode(preferences.getString('recovery_state')!)
            as Map<String, dynamic>;

    expect(
      migratedState['relapseCooldownUntil'],
      DateTime(2026, 8, 2).toIso8601String(),
    );
    expect(migratedState['cooldownMinutes'], 20);
  });

  test(
    'malformed current event state stays untouched with a recovery error',
    () async {
      final stored = jsonEncode({
        'stateVersion': RecoveryController.stateVersion,
        'events': [42],
        'riskReminders': false,
      });
      SharedPreferences.setMockInitialValues({'recovery_state': stored});
      final controller = RecoveryController(
        relapseLock: _FakeRelapseLockGateway(),
      );
      await controller.load();

      await controller.load();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('recovery_state'), stored);
      expect(controller.isLoaded, isFalse);
      expect(controller.loadStatus, RecoveryLoadStatus.error);
    },
  );

  test(
    'relapse debrief is attached to the relapse that opened cooldown',
    () async {
      final controller = RecoveryController(
        relapseLock: _FakeRelapseLockGateway(),
      );
      await controller.load();
      final relapse = RecoveryEvent.create(type: RecoveryEventType.relapse);
      controller.events.addAll([
        relapse,
        RecoveryEvent.create(type: RecoveryEventType.settingsChange),
      ]);
      controller.relapseCooldownEventId = relapse.id;
      controller.relapseCooldownUntil = DateTime.now();

      await controller.clearRelapseCooldown('stress');

      expect(
        controller.events
            .firstWhere((event) => event.id == relapse.id)
            .metadata,
        containsPair('debrief', 'stress'),
      );
      expect(
        controller.events
            .firstWhere(
              (event) => event.type == RecoveryEventType.settingsChange,
            )
            .metadata,
        isEmpty,
      );
    },
  );

  test('history deletion uses relapse-lock authentication', () async {
    final lock = _FakeRelapseLockGateway();
    final controller = RecoveryController(relapseLock: lock);
    await controller.load();
    final baseline = RecoveryEvent.create(
      type: RecoveryEventType.recoveryStart,
    );
    final craving = RecoveryEvent.create(
      type: RecoveryEventType.craving,
      metadata: {'intensity': 7, 'trigger': 'Stress', 'note': ''},
    );
    controller.events.addAll([baseline, craving]);
    await controller.enableRelapseLock('2468');

    expect(
      await controller.deleteEvent(
        id: craving.id,
        pin: '1111',
        tryBiometrics: false,
      ),
      ProtectedActionResult.denied,
    );
    expect(controller.events.any((event) => event.id == craving.id), isTrue);
    expect(
      await controller.deleteEvent(
        id: craving.id,
        pin: '2468',
        tryBiometrics: false,
      ),
      ProtectedActionResult.completed,
    );
    expect(controller.events.any((event) => event.id == craving.id), isFalse);
    expect(
      await controller.deleteEvent(
        id: baseline.id,
        pin: '2468',
        tryBiometrics: false,
      ),
      ProtectedActionResult.denied,
    );
  });

  test('completed SOS session preserves its linked debrief', () async {
    final controller = RecoveryController(
      relapseLock: _FakeRelapseLockGateway(),
    );
    await controller.load();
    final started = DateTime(2026, 8, 20, 20);

    await controller.recordSosSession(
      SosSession(
        id: 'sos-test',
        startedAt: started,
        completedAt: started.add(const Duration(minutes: 1)),
        debrief: 'down',
      ),
    );

    final completion = controller.events.singleWhere(
      (event) => event.type == RecoveryEventType.sosComplete,
    );
    expect(completion.metadata['startId'], 'sos-test');
    expect(completion.metadata['debrief'], 'down');
    expect(controller.sosSessions.single.debrief, 'down');
  });

  test('live SOS is persisted at start and completion is idempotent', () async {
    final controller = RecoveryController(
      relapseLock: _FakeRelapseLockGateway(),
    );
    await controller.load();
    final started = DateTime(2026, 8, 20, 21);

    final id = await controller.startSosSession(
      id: 'live-sos',
      startedAt: started,
    );
    expect(id, 'live-sos');
    expect(controller.sosSessions.single.isCompleted, isFalse);

    final completed = started.add(const Duration(minutes: 1));
    await controller.completeSosSession(startId: id, completedAt: completed);
    await controller.completeSosSession(
      startId: id,
      completedAt: completed,
      debrief: 'same',
    );

    expect(
      controller.events.where(
        (event) => event.type == RecoveryEventType.sosComplete,
      ),
      hasLength(1),
    );
    expect(controller.sosSessions.single.debrief, 'same');
  });

  test('SOS start rejects an ID already owned by another event', () async {
    final controller = RecoveryController(
      relapseLock: _FakeRelapseLockGateway(),
    );
    await controller.load();
    controller.events.add(
      RecoveryEvent.fromJson({
        'id': 'shared-id',
        'type': RecoveryEventType.craving.name,
        'timestamp': DateTime(2026, 8, 20, 21).toIso8601String(),
        'metadata': {'intensity': 5, 'trigger': 'stress'},
      }),
    );

    await expectLater(
      controller.startSosSession(id: 'shared-id'),
      throwsStateError,
    );
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
