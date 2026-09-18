import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/services/relapse_lock_service.dart';

void main() {
  test('new PINs are salted and hashed instead of stored as readable text', () async {
    final storage = _MemoryLockStorage();
    final service = _service(storage);

    await service.savePin('24681357');

    final stored = storage.values['relapse_lock_pin'];
    expect(stored, startsWith(r'pbkdf2-sha256$v1$'));
    expect(stored, isNot(contains('24681357')));
    expect(
      await service.verifyPin('00000000'),
      PinVerificationResult.denied,
    );
    expect(
      await service.verifyPin('24681357'),
      PinVerificationResult.verified,
    );
  });

  test('an existing readable PIN migrates after successful verification', () async {
    final storage = _MemoryLockStorage()
      ..values['relapse_lock_pin'] = '2468';
    final service = _service(storage);

    expect(
      await service.verifyPin('2468'),
      PinVerificationResult.verified,
    );
    expect(
      storage.values['relapse_lock_pin'],
      startsWith(r'pbkdf2-sha256$v1$'),
    );
  });

  test('repeated failures persist a temporary lockout', () async {
    var now = DateTime(2026, 9, 19, 12);
    final storage = _MemoryLockStorage();
    final service = _service(
      storage,
      now: () => now,
      maximumFailedAttempts: 3,
    );
    await service.savePin('2468');

    expect(await service.verifyPin('1111'), PinVerificationResult.denied);
    expect(await service.verifyPin('2222'), PinVerificationResult.denied);
    expect(await service.verifyPin('3333'), PinVerificationResult.lockedOut);
    expect(await service.verifyPin('2468'), PinVerificationResult.lockedOut);

    now = now.add(const Duration(minutes: 5, seconds: 1));
    expect(await service.verifyPin('2468'), PinVerificationResult.verified);
  });

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
