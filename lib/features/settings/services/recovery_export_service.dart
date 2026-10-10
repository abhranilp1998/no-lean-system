import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/presentation/backup_preview_sheet.dart';
import '../../recovery/presentation/relapse_auth_dialog.dart';
import '../../recovery/services/backup_service.dart';

/// Saves a JSON backup. Cancelling the Save screen shows nothing: no error
/// and no false "ready" notice.
Future<void> exportRecoveryData(
  BuildContext context,
  RecoveryController recovery, {
  BackupService? service,
}) async {
  try {
    final saved = await (service ?? BackupService()).exportBackup(
      recovery.events,
      preferences: recovery.portablePreferences,
      zones: recovery.zones,
    );
    if (saved && context.mounted) {
      AppNotice.show(
        context,
        'RECOVERY EXPORT READY // SECURE PIN EXCLUDED.',
        type: AppNoticeType.success,
      );
    }
  } catch (error) {
    if (context.mounted) {
      AppNotice.show(
        context,
        error is FormatException
            ? 'EXPORT FAILED // ${error.message}'
            : 'EXPORT FAILED // YOUR LOCAL DATA IS STILL INTACT.',
        type: AppNoticeType.error,
      );
    }
  }
}

Future<void> exportRecoveryCsv(
  BuildContext context,
  RecoveryController recovery, {
  BackupService? service,
}) async {
  try {
    final saved = await (service ?? BackupService()).exportEventsCsv(
      recovery.events,
    );
    if (saved && context.mounted) {
      AppNotice.show(
        context,
        'CSV READY // ${recovery.events.length} EVENTS. NOTES ARE INCLUDED: SHARE WITH CARE.',
        type: AppNoticeType.success,
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppNotice.show(
        context,
        'CSV EXPORT FAILED // YOUR LOCAL DATA IS STILL INTACT.',
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
      final recovery = ref.read(recoveryProvider);
      var result = await recovery.mergeImportedEvents(
        preview.events,
        importedZones: preview.zones,
        preferences: preview.preferences,
        restorePreferences: choice.restorePreferences,
      );
      if (result == ProtectedActionResult.authenticationRequired &&
          context.mounted) {
        final pin = await showRelapsePinDialog(
          context,
          actionLabel: 'MERGE BACKUP',
        );
        if (pin == null) return;
        result = await recovery.mergeImportedEvents(
          preview.events,
          importedZones: preview.zones,
          preferences: preview.preferences,
          restorePreferences: choice.restorePreferences,
          pin: pin,
          tryBiometrics: false,
        );
      }
      if (result != ProtectedActionResult.completed) {
        if (context.mounted) {
          AppNotice.show(
            context,
            result == ProtectedActionResult.lockedOut
                ? result.failureMessage
                : 'Authentication failed. History was not changed.',
            type: AppNoticeType.error,
          );
        }
        return;
      }
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
