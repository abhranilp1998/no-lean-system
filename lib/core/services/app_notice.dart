import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';
import 'app_feedback.dart';

enum AppNoticeType { info, success, warning, error }

/// High-visibility, consistently positioned in-app notices.
abstract final class AppNotice {
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    AppNoticeType type = AppNoticeType.info,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final visuals = NoLeanVisuals.of(context);
    final accent = _accent(type);
    final icon = _icon(type);

    switch (type) {
      case AppNoticeType.info:
        AppFeedback.tap(strength: AppFeedbackStrength.subtle);
      case AppNoticeType.success:
        AppFeedback.success();
      case AppNoticeType.warning:
        AppFeedback.warning();
      case AppNoticeType.error:
        AppFeedback.error();
    }

    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: duration,
        elevation: 14,
        dismissDirection: DismissDirection.horizontal,
        showCloseIcon: true,
        closeIconColor: Colors.white,
        backgroundColor: visuals.highContrast
            ? Colors.black
            : panelRaised.withValues(alpha: .98),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: accent.withValues(
              alpha: visuals.accentOpacity(.86, minimum: .72),
            ),
            width: visuals.highContrast ? 1.5 : 1,
          ),
        ),
        content: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  letterSpacing: .15,
                ),
              ),
            ),
          ],
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: accent,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  static Color _accent(AppNoticeType type) => switch (type) {
    AppNoticeType.info => cyan,
    AppNoticeType.success => toxic,
    AppNoticeType.warning => magenta,
    AppNoticeType.error => red,
  };

  static IconData _icon(AppNoticeType type) => switch (type) {
    AppNoticeType.info => Icons.info_outline,
    AppNoticeType.success => Icons.check_circle_outline,
    AppNoticeType.warning => Icons.warning_amber_rounded,
    AppNoticeType.error => Icons.error_outline,
  };
}
