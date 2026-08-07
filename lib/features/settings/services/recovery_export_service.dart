import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
        'lastDose': recovery.lastDose.toIso8601String(),
        'currentStreakDays': recovery.streak,
        'longestStreakDays': recovery.longestStreak,
        'dailySpend': recovery.dailySpend,
        'cravings': recovery.cravings.map((entry) => entry.toJson()).toList(),
        'reasons': recovery.reasons,
      }),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'NO LEAN recovery export',
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('EXPORT FAILED. YOUR LOCAL DATA IS STILL INTACT.'),
        ),
      );
    }
  }
}
