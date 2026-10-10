import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/services/relapse_lock_service.dart';

void main() {
  test(
    'new PINs are salted and hashed instead of stored as readable text',
    () async {
      final storage = _MemoryLockStorage();
      final service = _service(storage);

      await service.savePin('24681357');

      final stored = storage.values['relapse_lock_pin'];
      expect(stored, startsWith(r'pbkdf2-sha256$v1$'));
      expect(stored, isNot(contains('24681357')));
      expect(await service.verifyPin('00000000'), PinVerificationResult.denied);
      expect(
        await service.verifyPin('24681357'),
        PinVerificationResult.verified,
      );
    },
  );

  test(
    'an existing readable PIN migrates after successful verification',
    () async {
      final storage = _MemoryLockStorage()..values['relapse_lock_pin'] = '2468';
      final service = _service(storage);

      expect(await service.verifyPin('2468'), PinVerificationResult.verified);
      expect(
        storage.values['relapse_lock_pin'],
        startsWith(r'pbkdf2-sha256$v1$'),
      );
    },
  );

  test('repeated failures persist a temporary lockout', () async {
    var now = DateTime(2026, 9, 19, 12);
    final storage = _MemoryLockStorage();
    final service = _service(storage, now: () => now, maximumFailedAttempts: 3);
    await service.savePin('2468');

    expect(await service.verifyPin('1111'), PinVerificationResult.denied);
    expect(await service.verifyPin('2222'), PinVerificationResult.denied);
    expect(await service.verifyPin('3333'), PinVerificationResult.lockedOut);
    expect(await service.verifyPin('2468'), PinVerificationResult.lockedOut);

    now = now.add(const Duration(minutes: 5, seconds: 1));
    expect(await service.verifyPin('2468'), PinVerificationResult.verified);
  });

  test('repeat lockouts escalate 5, 15, then 60 minutes', () async {
    var now = DateTime(2026, 10, 8, 18);
    final storage = _MemoryLockStorage();
    final service = _service(storage, now: () => now, maximumFailedAttempts: 2);
    await service.savePin('2468');

    Future<void> failUntilLocked() async {
      expect(await service.verifyPin('0000'), PinVerificationResult.denied);
      expect(await service.verifyPin('0000'), PinVerificationResult.lockedOut);
    }

    for (final minutes in [5, 15, 60, 60]) {
      await failUntilLocked();
      expect(
        await service.lockedOutUntil(),
        now.add(Duration(minutes: minutes)),
      );
      now = now.add(Duration(minutes: minutes) - const Duration(seconds: 1));
      expect(await service.verifyPin('2468'), PinVerificationResult.lockedOut);
      now = now.add(const Duration(seconds: 2));
      expect(await service.lockedOutUntil(), isNull);
    }
  });

  test(
    'the escalation level survives a restart and resets on success',
    () async {
      var now = DateTime(2026, 10, 8, 18);
      final storage = _MemoryLockStorage();
      var service = _service(storage, now: () => now, maximumFailedAttempts: 1);
      await service.savePin('2468');

      expect(await service.verifyPin('0000'), PinVerificationResult.lockedOut);
      now = now.add(const Duration(minutes: 6));

      // A new service instance reads the same secure storage, like a restart.
      service = _service(storage, now: () => now, maximumFailedAttempts: 1);
      expect(await service.verifyPin('0000'), PinVerificationResult.lockedOut);
      expect(
        await service.lockedOutUntil(),
        now.add(const Duration(minutes: 15)),
      );

      now = now.add(const Duration(minutes: 16));
      expect(await service.verifyPin('2468'), PinVerificationResult.verified);
      expect(await service.verifyPin('0000'), PinVerificationResult.lockedOut);
      expect(
        await service.lockedOutUntil(),
        now.add(const Duration(minutes: 5)),
      );
    },
  );

  test('clearing the lock removes the credential and attempt state', () async {
    final storage = _MemoryLockStorage();
    final service = _service(storage, maximumFailedAttempts: 1);
    await service.savePin('2468');
    await service.verifyPin('0000');

    await service.clearPin();

    expect(await service.hasPin(), isFalse);
    expect(storage.values, isEmpty);
  });
}

SecureRelapseLockService _service(
  _MemoryLockStorage storage, {
  DateTime Function()? now,
  int maximumFailedAttempts = 5,
}) => SecureRelapseLockService(
  lockStorage: storage,
  pinHasher: RelapsePinHasher(iterations: 32, random: Random(7)),
  now: now,
  maximumFailedAttempts: maximumFailedAttempts,
);

class _MemoryLockStorage implements RelapseLockStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
