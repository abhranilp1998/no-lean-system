import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../application/recovery_controller.dart';
import '../application/recovery_provider.dart';
import '../services/backup_service.dart';

/// A failed/unsupported read never presents a fresh, writable recovery history.
class RecoveryStartupScreen extends ConsumerWidget {
  const RecoveryStartupScreen({super.key});

  Future<void> _export(
    BuildContext context,
    RecoveryController recovery,
  ) async {
    try {
      final copies = await recovery.recoveryCopies();
      final sanitized = <Object?>[];
      Object? withoutSecrets(Object? value) {
        if (value is Map) {
          return {
            for (final entry in value.entries)
              if (!{'pin', 'relapsePin', 'trustedContact'}.contains(entry.key))
                entry.key: withoutSecrets(entry.value),
          };
        }
        if (value is List) return value.map(withoutSecrets).toList();
        return value;
      }

      for (final copy in copies) {
        try {
          sanitized.add(withoutSecrets(jsonDecode(copy)));
        } on FormatException {
          /* Leave unreadable originals untouched. */
        }
      }
      if (sanitized.isEmpty) {
        throw const FormatException(
          'No readable copy is available to export. The originals remain on this device.',
        );
      }
      await BackupService().exportJson(
        jsonEncode({
          'recoveryCopiesVersion': 1,
          'copies': sanitized,
          'unreadableCopies': copies.length - sanitized.length,
        }),
      );
    } catch (error) {
      if (context.mounted) {
        AppNotice.show(
          context,
          error is FormatException
              ? error.message
              : 'Export could not finish. Your original data remains on this device.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final loading = recovery.loadStatus == RecoveryLoadStatus.loading;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('NO LEAN', style: displayFont(fontSize: 24, color: cyan)),
                const SizedBox(height: 20),
                if (loading) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text('Opening your recovery history…'),
                ] else ...[
                  const Icon(Icons.history, color: cyan, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    recovery.loadMessage ?? 'Your history could not be opened.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Keep the app installed to preserve its local data. You can retry or save readable copies for recovery.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: recovery.retryLoad,
                    child: const Text('RETRY'),
                  ),
                  TextButton(
                    onPressed: () => _export(context, recovery),
                    child: const Text('EXPORT PRESERVED DATA'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
