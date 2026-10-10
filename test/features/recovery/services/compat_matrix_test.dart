import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../../support/recovery_fakes.dart';

/// Pre-merge compatibility matrix: every backup format and every stored
/// state version the app has ever written must still load.
void main() {
  final pledge = {
    'id': 'p-1',
    'type': 'pledge',
    'timestamp': DateTime(2026, 1, 1, 9).toIso8601String(),
    'metadata': <String, dynamic>{},
  };

  for (var format = 1; format <= BackupService.currentBackupVersion; format++) {
    test('backup format $format imports', () {
      final preview = BackupService().validateBackupJson(
        jsonEncode({
          'version': format,
          'events': [pledge],
          'preferences': <String, dynamic>{},
        }),
      );
      expect(preview.eventCount, 1);
    });
  }

  test('a backup from a newer app is refused with a clear message', () {
    expect(
      () => BackupService().validateBackupJson(
        jsonEncode({
          'version': BackupService.currentBackupVersion + 1,
          'events': [],
        }),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported backup version'),
        ),
      ),
    );
  });

  for (var version = 2; version <= RecoveryController.stateVersion; version++) {
    test('stored state v$version loads and is upgraded to current', () async {
      final store = MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': version,
          'lastDose': DateTime(2026, 1, 1).toIso8601String(),
          'events': version < 6 ? null : [pledge],
        }),
      );
      final controller = RecoveryController(
        store: store,
        relapseLock: FakeRelapseLock(),
        now: () => DateTime(2026, 2, 1),
      );
      await controller.load();
      expect(controller.loadStatus, RecoveryLoadStatus.ready);
      final saved = jsonDecode(store.value!) as Map<String, dynamic>;
      expect(saved['stateVersion'], RecoveryController.stateVersion);
    });
  }
}
