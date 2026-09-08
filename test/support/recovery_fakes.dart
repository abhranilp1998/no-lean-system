import 'package:no_lean/features/recovery/services/recovery_state_store.dart';
import 'package:no_lean/features/recovery/services/relapse_lock_service.dart';

class MemoryRecoveryStore implements RecoveryStateStore {
  MemoryRecoveryStore([this.value]);
  String? value;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;
  int activeWrites = 0;
  int maxConcurrentWrites = 0;
  Duration delay = Duration.zero;
  final copies = <String>[];

  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Read unavailable');
    return value;
  }

  @override
  Future<void> write(String next) async {
    activeWrites++;
    if (activeWrites > maxConcurrentWrites) maxConcurrentWrites = activeWrites;
    try {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (failWrite) throw StateError('Disk full');
      value = next;
      writes++;
    } finally {
      activeWrites--;
    }
  }

  @override
  Future<void> preserve(String value) async {
    if (!copies.contains(value)) copies.add(value);
  }

  @override
  Future<List<String>> recoveryCopies() async => List.of(copies);
  @override
  Future<void> removeLegacyPin() async {}
}

class FakeRelapseLock implements RelapseLockGateway {
  String? pin;
  int challenges = 0;
  @override
  Future<BiometricAuthResult> authenticateBiometrically({
    required String reason,
  }) async {
    challenges++;
    return BiometricAuthResult.unavailable;
  }

  @override
  Future<void> clearPin() async {
    pin = null;
  }

  @override
  Future<bool> hasPin() async => pin != null;
  @override
  Future<void> savePin(String value) async {
    pin = value;
  }

  @override
  Future<bool> verifyPin(String value) async => pin == value;
}
