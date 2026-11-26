import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/layout/tab_layout.dart';
import '../../../core/services/app_feedback.dart';
import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glow_button.dart';
import '../../companion/presentation/companion_common.dart';
import '../../companion/presentation/struggling_screen.dart';
import '../../companion/presentation/urge_surf_screen.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/presentation/relapse_log_sheet.dart';
import 'dashboard_dialogs.dart';

import '../../recovery/presentation/relapse_cooldown_screen.dart';

import '../../settings/presentation/trusted_contact_dialog.dart';
import '../../settings/services/trusted_contact_service.dart';
import '../domain/rough_day.dart';
import 'widgets/dashboard_notice_center.dart';

/// Calm, simplified home used during a rough day. Three big actions, warm
/// copy from the user's own logs, and a way back to the normal view.
class RoughDayHome extends ConsumerWidget {
  const RoughDayHome({
    super.key,
    this.launchUri,
    this.contactOverride,
    this.lookupContact = true,
    this.onRideItOut,
    this.onLogNow,
  });

  /// Test seam for opening the phone dialer.
  final Future<bool> Function(Uri uri)? launchUri;

  /// Test seam so widget tests do not need secure storage.
  final TrustedContact? contactOverride;

  /// When false, [contactOverride] is used as-is (including null).
  final bool lookupContact;

  /// Test seam; defaults to the existing urge-surf screen.
  final VoidCallback? onRideItOut;

  /// Test seam; defaults to the relapse logger.
  final VoidCallback? onLogNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final seed = recovery.roughDayStartedAt?.millisecondsSinceEpoch ?? 0;
    final copy = roughDayCopy(
      events: recovery.events,
      now: DateTime.now(),
      longestStreak: recovery.longestStreak,
      seed: seed,
    );
    return TabListView(
      children: [
        const SizedBox(height: 8),
        Text('ROUGH DAY', style: eyebrowStyle.copyWith(color: cyan)),
        const SizedBox(height: 10),
        Text(
          copy.headline,
          style: displayFont(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ).copyWith(height: 1.2),
        ),
        const SizedBox(height: 12),
        Text(
          copy.body,
          style: const TextStyle(fontSize: 15, height: 1.45, color: muted),
        ),
        if (recovery.welcomeBackSince != null ||
            recovery.relapseCooldownUntil != null) ...[
          const SizedBox(height: 16),
          DashboardNoticeCenter(
            style: recovery.dashboardNoticeStyle,
            showWelcomeBack: recovery.welcomeBackSince != null,
            showResetSupport: recovery.relapseCooldownUntil != null,
            onLogMissedRelapses: () => showRelapseDialog(context, ref),
            onOpenResetSupport: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RelapseCooldownScreen()),
            ),
            onLogMoreEvents: () => showRelapseDialog(context, ref),
          ),
        ],
        const SizedBox(height: 28),
        GlowButton(
          key: const ValueKey('rough-day-call'),
          label: roughDayCallLabel,
          icon: Icons.phone_outlined,
          color: toxic,
          onTap: () => unawaitedCall(context, ref),
        ),
        const SizedBox(height: 14),
        GlowButton(
          key: const ValueKey('rough-day-ride'),
          label: roughDayRideLabel,
          icon: Icons.waves,
          color: cyan,
          onTap: () {
            if (onRideItOut != null) {
              onRideItOut!();
              return;
            }
            UrgeSurfScreen.open(context);
          },
        ),
        const SizedBox(height: 14),
        GlowButton(
          key: const ValueKey('rough-day-log-later'),
          label: roughDayLogLaterLabel,
          icon: Icons.schedule,
          color: magenta,
          onTap: () => showLogLaterSheet(context, recovery, onLogNow: onLogNow),
        ),
        const SizedBox(height: 28),
        TextButton(
          key: const ValueKey('rough-day-back'),
          onPressed: () async {
            AppFeedback.tap();
            await recovery.clearRoughDay();
          },
          child: const Text(roughDayBackLabel),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('rough-day-more-help'),
          onPressed: () => StrugglingScreen.open(context),
          child: const Text('More right-now help'),
        ),
      ],
    );
  }

  Future<void> unawaitedCall(BuildContext context, WidgetRef ref) async {
    TrustedContact? contact = contactOverride;
    if (contact == null && lookupContact) {
      try {
        contact = await ref.read(trustedContactProvider.future);
      } catch (_) {
        contact = null;
      }
    }
    if (!context.mounted) return;
    if (contact == null) {
      AppNotice.show(
        context,
        roughDayCallEmptyMessage,
        actionLabel: 'ADD',
        onAction: () => showTrustedContactDialog(context, ref),
      );
      return;
    }
    final launch =
        launchUri ??
        ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
    try {
      final opened = await launch(Uri(scheme: 'tel', path: contact.phone));
      if (!opened && context.mounted) {
        AppNotice.show(
          context,
          'I could not open the phone app. You can call ${contact.phone} yourself.',
          type: AppNoticeType.error,
        );
      }
    } catch (_) {
      if (context.mounted) {
        AppNotice.show(
          context,
          'I could not open the phone app. You can call ${contact.phone} yourself.',
          type: AppNoticeType.error,
        );
      }
    }
  }
}

/// "Log it later": set a gentle reminder, or open the logger now.
Future<void> showLogLaterSheet(
  BuildContext context,
  RecoveryController recovery, {
  VoidCallback? onLogNow,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              roughDayLogLaterPrompt,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('rough-day-log-remind'),
              onPressed: () async {
                final at = await recovery.remindToLogLater();
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  AppNotice.show(
                    context,
                    at == null
                        ? roughDayReminderFailedMessage
                        : roughDayReminderSetMessage(at),
                  );
                }
              },
              child: const Text(roughDayRemindLabel),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const ValueKey('rough-day-log-now'),
              onPressed: () {
                Navigator.pop(ctx);
                if (onLogNow != null) {
                  onLogNow();
                  return;
                }
                showRelapseLogSheet(context, source: 'rough_day');
              },
              child: const Text(roughDayLogNowLabel),
            ),
          ],
        ),
      );
    },
  );
}
