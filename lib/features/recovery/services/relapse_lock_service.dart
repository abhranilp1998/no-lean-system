import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricAuthResult { authenticated, unavailable, denied }

enum PinVerificationResult { verified, denied, lockedOut }

abstract interface class RelapseLockStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureRelapseLockStorage implements RelapseLockStorage {
  SecureRelapseLockStorage([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'no_lean_relapse_lock'),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class RelapsePinHasher {
  RelapsePinHasher({this.iterations = 120000, Random? random})
    : assert(iterations > 0),
      _random = random ?? Random.secure();

  static const _algorithm = 'pbkdf2-sha256';
  static const _version = 'v1';
  static const _saltLength = 16;
  static const _derivedKeyLength = 32;

  final int iterations;
  final Random _random;

  bool isEncodedHash(String value) => value.startsWith('$_algorithm\$');

  String hash(String pin) {
    final salt = List<int>.generate(
      _saltLength,
      (_) => _random.nextInt(256),
      growable: false,
    );
    final digest = _deriveKey(utf8.encode(pin), salt, iterations);
    return [
      _algorithm,
      _version,
      iterations.toString(),
      base64UrlEncode(salt),
      base64UrlEncode(digest),
    ].join(r'$');
  }

  bool verify(String pin, String encoded) {
    try {
      final parts = encoded.split(r'$');
      if (parts.length != 5 || parts[0] != _algorithm || parts[1] != _version) {
        return false;
      }
      final rounds = int.parse(parts[2]);
      if (rounds <= 0 || rounds > 1000000) return false;
      final salt = base64Url.decode(parts[3]);
      final expected = base64Url.decode(parts[4]);
      if (salt.length != _saltLength || expected.length != _derivedKeyLength) {
        return false;
      }
      final actual = _deriveKey(utf8.encode(pin), salt, rounds);
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  static Uint8List _deriveKey(
    List<int> password,
    List<int> salt,
    int iterations,
  ) {
    const blockIndex = <int>[0, 0, 0, 1];
    final hmac = Hmac(sha256, password);
    var u = hmac.convert([...salt, ...blockIndex]).bytes;
    final result = Uint8List.fromList(u);
    for (var round = 1; round < iterations; round++) {
      u = hmac.convert(u).bytes;
      for (var index = 0; index < result.length; index++) {
        result[index] ^= u[index];
      }
    }
    return Uint8List.sublistView(result, 0, _derivedKeyLength);
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = min(left.length, right.length);
    for (var index = 0; index < length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

abstract interface class RelapseLockGateway {
  Future<bool> hasPin();

  Future<void> savePin(String pin);

  Future<void> clearPin();

  Future<PinVerificationResult> verifyPin(String pin);

  Future<BiometricAuthResult> authenticateBiometrically({
    required String reason,
  });
}

class SecureRelapseLockService implements RelapseLockGateway {
  SecureRelapseLockService({
    FlutterSecureStorage? storage,
    RelapseLockStorage? lockStorage,
    LocalAuthentication? localAuthentication,
    RelapsePinHasher? pinHasher,
    DateTime Function()? now,
    this.maximumFailedAttempts = 5,
    this.lockoutSchedule = defaultLockoutSchedule,
  }) : assert(storage == null || lockStorage == null),
       assert(maximumFailedAttempts > 0),
       assert(lockoutSchedule.isNotEmpty),
       _storage = lockStorage ?? SecureRelapseLockStorage(storage),
       _pinHasher = pinHasher ?? RelapsePinHasher(),
       _now = now ?? DateTime.now,
       _localAuthentication = localAuthentication ?? LocalAuthentication();

  static final instance = SecureRelapseLockService();

  static const _pinKey = 'relapse_lock_pin';
  static const _failedAttemptsKey = 'relapse_lock_failed_attempts';
  static const _lockedUntilKey = 'relapse_lock_locked_until';
  static const _lockoutLevelKey = 'relapse_lock_lockout_level';

  /// Each consecutive lockout lasts longer. The level survives restarts and
  /// expiry; only a verified PIN, a new PIN or clearing the lock resets it.
  static const defaultLockoutSchedule = <Duration>[
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 60),
  ];

  final RelapseLockStorage _storage;
  final RelapsePinHasher _pinHasher;
  final DateTime Function() _now;
  final LocalAuthentication _localAuthentication;
  final int maximumFailedAttempts;
  final List<Duration> lockoutSchedule;

  /// Duration applied to the lockout with [level] (1-based); levels past the
  /// end of the schedule reuse its longest step.
  Duration lockoutDurationForLevel(int level) =>
      lockoutSchedule[(level - 1).clamp(0, lockoutSchedule.length - 1)];

  @override
  Future<bool> hasPin() async => (await _storage.read(_pinKey)) != null;

  @override
  Future<void> savePin(String pin) async {
    await _storage.write(_pinKey, await _hashPin(pin));
    await _clearFailures();
    await _storage.delete(_lockoutLevelKey);
  }

  @override
  Future<void> clearPin() async {
    await _storage.delete(_pinKey);
    await _clearFailures();
    await _storage.delete(_lockoutLevelKey);
  }

  @override
  Future<PinVerificationResult> verifyPin(String pin) async {
    if (await _isLockedOut()) return PinVerificationResult.lockedOut;

    final storedPin = await _storage.read(_pinKey);
    if (storedPin == null) return PinVerificationResult.denied;

    final isHashed = _pinHasher.isEncodedHash(storedPin);
    final matches = isHashed
        ? await _verifyHashedPin(pin, storedPin)
        : _constantTimeEquals(utf8.encode(pin), utf8.encode(storedPin));
    if (matches) {
      if (!isHashed) {
        // Existing installs used a plaintext value inside encrypted storage.
        // Upgrade it only after proving the user knows that value.
        await _storage.write(_pinKey, await _hashPin(pin));
      }
      await _clearFailures();
      await _storage.delete(_lockoutLevelKey);
      return PinVerificationResult.verified;
    }

    final attempts =
        (int.tryParse(await _storage.read(_failedAttemptsKey) ?? '') ?? 0) + 1;
    if (attempts >= maximumFailedAttempts) {
      final level =
          (int.tryParse(await _storage.read(_lockoutLevelKey) ?? '') ?? 0) + 1;
      final lockedUntil = _now().add(lockoutDurationForLevel(level));
      await _storage.write(_failedAttemptsKey, '0');
      await _storage.write(_lockoutLevelKey, level.toString());
      await _storage.write(_lockedUntilKey, lockedUntil.toIso8601String());
      return PinVerificationResult.lockedOut;
    }
    await _storage.write(_failedAttemptsKey, attempts.toString());
    return PinVerificationResult.denied;
  }

  /// When PIN entry is paused, the moment it becomes available again.
  Future<DateTime?> lockedOutUntil() async {
    final encoded = await _storage.read(_lockedUntilKey);
    final lockedUntil = encoded == null ? null : DateTime.tryParse(encoded);
    if (lockedUntil == null || !_now().isBefore(lockedUntil)) return null;
    return lockedUntil;
  }

  Future<bool> _isLockedOut() async {
    final encoded = await _storage.read(_lockedUntilKey);
    final lockedUntil = encoded == null ? null : DateTime.tryParse(encoded);
    if (lockedUntil == null) return false;
    if (_now().isBefore(lockedUntil)) return true;
    // Expiry clears the attempt counter but keeps the escalation level.
    await _clearFailures();
    return false;
  }

  Future<void> _clearFailures() async {
    await _storage.delete(_failedAttemptsKey);
    await _storage.delete(_lockedUntilKey);
  }

  Future<String> _hashPin(String pin) => compute(_hashPinInBackground, (
    pin: pin,
    iterations: _pinHasher.iterations,
  ));

  Future<bool> _verifyHashedPin(String pin, String encoded) =>
      compute(_verifyPinInBackground, (pin: pin, encoded: encoded));

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = min(left.length, right.length);
    for (var index = 0; index < length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  @override
  Future<BiometricAuthResult> authenticateBiometrically({
    required String reason,
  }) async {
    try {
      final supported = await _localAuthentication.isDeviceSupported();
      final enrolled = await _localAuthentication.getAvailableBiometrics();
      if (!supported || enrolled.isEmpty) {
        return BiometricAuthResult.unavailable;
      }

      final authenticated = await _localAuthentication.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
      return authenticated
          ? BiometricAuthResult.authenticated
          : BiometricAuthResult.denied;
    } catch (_) {
      return BiometricAuthResult.unavailable;
    }
  }
}

String _hashPinInBackground(({String pin, int iterations}) input) =>
    RelapsePinHasher(iterations: input.iterations).hash(input.pin);

bool _verifyPinInBackground(({String pin, String encoded}) input) =>
    RelapsePinHasher(iterations: 1).verify(input.pin, input.encoded);
