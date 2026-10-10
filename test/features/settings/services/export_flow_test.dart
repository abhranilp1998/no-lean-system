import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:no_lean/features/settings/services/recovery_export_service.dart';

import '../../../support/recovery_fakes.dart';

/// Records what would have been written and answers like the Save screen.
class _FakeSaver {
  _FakeSaver({this.saved = true, this.error});

  final bool saved;
  final Object? error;
  String? content;
  String? fileName;
  String? mimeType;

  Future<bool> call(
    String content, {
    required String fileName,
    required String mimeType,
    required String extension,
  }) async {
    if (error != null) throw error!;
    this.content = content;
    this.fileName = fileName;
    this.mimeType = mimeType;
    return saved;
  }
}

void main() {
  late RecoveryController recovery;

  setUp(() async {
    recovery = RecoveryController(
      store: MemoryRecoveryStore(),
      relapseLock: FakeRelapseLock(),
      now: () => DateTime(2026, 10, 10, 12),
    );
    await recovery.load();
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNoLeanTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('cancelling the JSON Save screen shows no notice at all', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    final saver = _FakeSaver(saved: false);
    await exportRecoveryData(
      context,
      recovery,
      service: BackupService(saver: saver.call),
    );
    await tester.pump();
    expect(saver.content, isNotNull);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a saved JSON backup shows the ready notice', (tester) async {
    final context = await pumpHost(tester);
    final saver = _FakeSaver();
    await exportRecoveryData(
      context,
      recovery,
      service: BackupService(saver: saver.call),
    );
    await tester.pump();
    expect(find.textContaining('RECOVERY EXPORT READY'), findsOneWidget);
    expect(saver.fileName, startsWith('nolean_backup_'));
    expect(saver.fileName, endsWith('.json'));
    expect(saver.mimeType, 'application/json');
  });

  testWidgets('a failed save shows an error, never success', (tester) async {
    final context = await pumpHost(tester);
    final saver = _FakeSaver(error: Exception('disk full'));
    await exportRecoveryData(
      context,
      recovery,
      service: BackupService(saver: saver.call),
    );
    await tester.pump();
    expect(find.textContaining('EXPORT FAILED'), findsOneWidget);
    expect(find.textContaining('READY'), findsNothing);
  });

  testWidgets('cancelling the CSV Save screen shows no notice at all', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    final saver = _FakeSaver(saved: false);
    await exportRecoveryCsv(
      context,
      recovery,
      service: BackupService(saver: saver.call),
    );
    await tester.pump();
    expect(saver.fileName, endsWith('.csv'));
    expect(find.byType(SnackBar), findsNothing);
  });

  test('exported JSON round-trips through import validation', () async {
    final events = [
      RecoveryEvent.create(
        type: RecoveryEventType.pledge,
        timestamp: DateTime(2026, 10, 1, 9),
      ),
      RecoveryEvent.create(
        type: RecoveryEventType.relapse,
        timestamp: DateTime(2026, 10, 2, 19),
      ),
    ];
    final saver = _FakeSaver();
    final service = BackupService(saver: saver.call);
    final saved = await service.exportBackup(
      events,
      preferences: recovery.portablePreferences,
    );
    expect(saved, isTrue);

    final payload = jsonDecode(saver.content!) as Map<String, dynamic>;
    expect(payload['version'], BackupService.currentBackupVersion);
    expect(payload.containsKey('relapsePin'), isFalse);

    // As written to disk (UTF-8), then read back by the import path.
    final bytes = utf8.encode(saver.content!);
    final preview = service.validateBackupJson(
      BackupService.decodeBackupBytes(bytes),
    );
    expect(preview.eventCount, 2);
    expect(preview.events.map((e) => e.id), events.map((e) => e.id));
    expect(
      preview.events.map((e) => jsonEncode(e.toJson())),
      events.map((e) => jsonEncode(e.toJson())),
    );

    // Same file re-saved with a BOM by another app still imports.
    final withBom = [0xEF, 0xBB, 0xBF, ...bytes];
    expect(
      service
          .validateBackupJson(BackupService.decodeBackupBytes(withBom))
          .eventCount,
      2,
    );
  });

  test('backups over 5 MB are refused before the Save screen opens', () {
    final saver = _FakeSaver();
    final service = BackupService(saver: saver.call);
    final huge = '{"pad":"${'x' * (BackupService.maxBackupBytes + 1)}"}';
    expect(() => service.exportJson(huge), throwsFormatException);
    expect(saver.content, isNull);
  });

  test('the emergency export is never blocked by the size limit', () async {
    final saver = _FakeSaver();
    final service = BackupService(saver: saver.call);
    final huge = '{"pad":"${'x' * (BackupService.maxBackupBytes + 1)}"}';
    expect(await service.exportJson(huge, enforceSizeLimit: false), isTrue);
    expect(saver.content, huge);
  });
}
