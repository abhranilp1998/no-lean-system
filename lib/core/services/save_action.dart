import 'package:flutter/material.dart';

import 'app_notice.dart';

/// Existing single-action controls report a failure without announcing success
/// or letting a platform/storage exception escape their event callback.
Future<bool> saveAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (_) {
    if (context.mounted) {
      AppNotice.show(
        context,
        'Could not save this change. Please try again. Your previous history is still intact.',
        type: AppNoticeType.error,
      );
    }
    return false;
  }
}
