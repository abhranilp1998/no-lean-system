import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('nolean-share-test-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test(
    'attachment remains readable after share returns with no competing text',
    () async {
      String? sharedPath;
      final service = BackupService(
        temporaryDirectory: () async => root,
        share: (params) async {
          expect(params.text, isNull);
          expect(params.files, hasLength(1));
          expect(params.files!.single.mimeType, 'application/json');
          sharedPath = params.files!.single.path;
          return const ShareResult('files', ShareResultStatus.success);
        },
      );
      final content = jsonEncode(
        service.buildBackupPayload(
          [],
          preferences: {
            'reasons': ['Clarity'],
          },
        ),
      );
      await service.shareBackupJson(content);
      // A receiving file manager reads after the sheet has returned.
      final received = await File(sharedPath!).readAsBytes();
      expect(utf8.decode(received), content);
      expect(
        service
            .validateBackupJson(utf8.decode(received))
            .preferences!['reasons'],
        ['Clarity'],
      );
    },
  );

  test(
    'rapid shares keep distinct source copies and age out only old exports',
    () async {
      final exports = await Directory('${root.path}/exports').create();
      final old = await File('${exports.path}/old.json').writeAsString('{}');
      await old.setLastModified(
        DateTime.now().subtract(const Duration(hours: 2)),
      );
      final paths = <String>[];
      final service = BackupService(
        temporaryDirectory: () async => root,
        share: (params) async {
          paths.add(params.files!.single.path);
          return const ShareResult('files', ShareResultStatus.success);
        },
      );
      await service.shareBackupJson('{"first":1}');
      await service.shareBackupJson('{"second":2}');
      expect(paths.toSet(), hasLength(2));
      expect(await File(paths.first).readAsString(), '{"first":1}');
      expect(await File(paths.last).readAsString(), '{"second":2}');
      expect(await old.exists(), isFalse);
    },
  );
}
