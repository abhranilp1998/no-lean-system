import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/app_notice.dart';
import '../../recovery/application/recovery_controller.dart';

Future<void> exportRecoveryData(
  BuildContext context,
  RecoveryController recovery,
) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/no_lean_recovery_export.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'exportedAt': DateTime.now().toIso8601String(),
        'stateVersion': RecoveryController.stateVersion,
        'lastDose': recovery.lastDose.toIso8601String(),
        'lastPledge': recovery.lastPledge?.toIso8601String(),
        'currentStreakDays': recovery.streak,
        'longestStreakDays': recovery.longestStreak,
        'dailySpend': recovery.dailySpend,
        'cravings': recovery.cravings.map((entry) => entry.toJson()).toList(),
        'sosSessions': recovery.sosSessions
            .map((session) => session.toJson())
            .toList(),
        'reasons': recovery.reasons,
        'reminderMessages': recovery.reminderMessages,
        'cleanDays': recovery.cleanDays,
        'riskWindow': recovery.riskWindow.toJson(),
        'settings': {
          'scanlines': recovery.scanlines,
          'reduceMotion': recovery.reduceMotion,
          'highContrast': recovery.highContrast,
          'riskReminders': recovery.riskReminders,
          'soundscape': recovery.soundscape,
          'effectIntensity': recovery.intensity.name,
          'relapseLockEnabled': recovery.requirePinAfterRelapse,
        },
        'securityNote':
            'Relapse-lock PIN and biometric material are intentionally excluded.',
      }),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'NO LEAN recovery export',
      ),
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
