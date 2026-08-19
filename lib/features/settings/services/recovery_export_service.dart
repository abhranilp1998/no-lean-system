import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/presentation/backup_preview_sheet.dart';
import '../../recovery/services/backup_service.dart';

Future<void> exportRecoveryData(
  BuildContext context,
  RecoveryController recovery,
) async {
  try {
    await BackupService().exportBackup(
      recovery.events,
      preferences: recovery.portablePreferences,
    );
    if (context.mounted) {
      AppNotice.show(
        context,
        'RECOVERY EXPORT READY // SECURE PIN EXCLUDED.',
        type: AppNoticeType.success,
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppNotice.show(
        context,
        'EXPORT FAILED // YOUR LOCAL DATA IS STILL INTACT.',
        type: AppNoticeType.error,
      );
    }
  }
}

Future<void> importRecoveryData(BuildContext context, WidgetRef ref) async {
  try {
    final service = BackupService();
    final preview = await service.pickAndValidateBackup();

    if (preview == null) return; // User canceled

    if (!context.mounted) return;

    final choice = await BackupPreviewSheet.show(context, preview);
    if (choice != null && context.mounted) {
      await ref
          .read(recoveryProvider)
          .mergeImportedEvents(
            preview.events,
            preferences: preview.preferences,
            restorePreferences: choice.restorePreferences,
          );
      if (context.mounted) {
        AppNotice.show(
          context,
          choice.restorePreferences
              ? 'BACKUP MERGED // EVENTS AND CUSTOMIZATIONS RESTORED.'
              : 'BACKUP MERGED // EVENTS UPDATED.',
          type: AppNoticeType.success,
        );
      }
    }
  } catch (error) {
    if (context.mounted) {
      final detail = error is FormatException
          ? error.message.toString()
          : 'The selected file could not be imported.';
      AppNotice.show(
        context,
        'IMPORT FAILED // $detail',
        type: AppNoticeType.error,
      );
    }
  }
}
