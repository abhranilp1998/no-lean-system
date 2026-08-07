import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricAuthResult { authenticated, unavailable, denied }

abstract interface class RelapseLockGateway {
  Future<bool> hasPin();

  Future<void> savePin(String pin);

  Future<void> clearPin();

  Future<bool> verifyPin(String pin);

  Future<BiometricAuthResult> authenticateBiometrically({
    required String reason,
  });
}

class SecureRelapseLockService implements RelapseLockGateway {
  SecureRelapseLockService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuthentication,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(storageNamespace: 'no_lean_relapse_lock'),
           ),
       _localAuthentication = localAuthentication ?? LocalAuthentication();

  static final instance = SecureRelapseLockService();

  static const _pinKey = 'relapse_lock_pin';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> hasPin() async => (await _storage.read(key: _pinKey)) != null;

  @override
  Future<void> savePin(String pin) => _storage.write(key: _pinKey, value: pin);

  @override
  Future<void> clearPin() => _storage.delete(key: _pinKey);

  @override
  Future<bool> verifyPin(String pin) async {
    final storedPin = await _storage.read(key: _pinKey);
    if (storedPin == null || storedPin.length != pin.length) return false;

    var difference = 0;
    for (var index = 0; index < storedPin.length; index++) {
      difference |= storedPin.codeUnitAt(index) ^ pin.codeUnitAt(index);
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
