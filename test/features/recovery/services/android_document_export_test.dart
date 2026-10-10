import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/services/android_document_export.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('no_lean/export');
  const exporter = AndroidDocumentExport();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'sends restorable UTF-8 bytes with JSON MIME and waits for completion',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'save');
        final args = call.arguments as Map;
        expect(args['mimeType'], 'application/json');
        expect(args['fileName'], endsWith('.json'));
        final bytes = args['bytes'] as Uint8List;
        final preview = BackupService().validateBackupJson(utf8.decode(bytes));
        expect(preview.preferences!['reasons'], ['বাংলা // ₹100']);
        return true;
      });
      final service = BackupService(
        saver:
            (
              content, {
              required fileName,
              required mimeType,
              required extension,
            }) =>
                exporter.save(content, fileName: fileName, mimeType: mimeType),
      );
      expect(
        await service.exportBackup(
          [],
          preferences: {
            'reasons': ['বাংলা // ₹100'],
          },
        ),
        isTrue,
      );
    },
  );

  test('cancellation returns false', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(
      await exporter.save(
        '{}',
        fileName: 'backup.json',
        mimeType: 'application/json',
      ),
      isFalse,
    );
  });

  test(
    'provider failure gives actionable error and never reports success',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'EXPORT_WRITE'),
      );
      await expectLater(
        exporter.save(
          '{}',
          fileName: 'backup.json',
          mimeType: 'application/json',
        ),
        throwsA(
          isA<ExportSaveException>().having(
            (e) => e.message,
            'message',
            contains('Downloads'),
          ),
        ),
      );
    },
  );

  test(
    'interruption and busy states stay distinct from cancellation',
    () async {
      for (final code in ['EXPORT_INTERRUPTED', 'EXPORT_BUSY']) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: code),
        );
        await expectLater(
          exporter.save('x', fileName: 'history.csv', mimeType: 'text/csv'),
          throwsA(isA<ExportSaveException>()),
        );
      }
    },
  );

  test('missing completion cannot become a ready notice', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
      exporter.save(
        '{}',
        fileName: 'backup.json',
        mimeType: 'application/json',
      ),
      throwsA(isA<ExportSaveException>()),
    );
  });
}
