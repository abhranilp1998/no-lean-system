import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/app_notice.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../companion/presentation/companion_common.dart';
import '../../../recovery/application/recovery_provider.dart';
import '../../../recovery/domain/swap_watch.dart';
import '../../../settings/services/trusted_contact_service.dart';

/// Gentle dashboard / weekly-view card when lean days drop but another
/// substance's days rise. Optional next step: call their own SOS contact
/// or a doctor. No government helpline, no Call 112.
class SwapWatchCard extends ConsumerStatefulWidget {
  const SwapWatchCard({
    required this.insight,
    this.onDismiss,
    this.launcher,
    this.contact,
    super.key,
  });

  final SwapWatchInsight insight;
  final VoidCallback? onDismiss;

  /// Test seam; defaults to the platform dialer.
  final Future<bool> Function(Uri uri)? launcher;

  /// Test seam; defaults to the saved trusted contact.
  final TrustedContact? contact;

  @override
  ConsumerState<SwapWatchCard> createState() => _SwapWatchCardState();
}

class _SwapWatchCardState extends ConsumerState<SwapWatchCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Failures are swallowed inside the controller.
      ref.read(recoveryProvider).offerSwapWatchNotification();
    });
  }

  SwapWatchInsight get insight => widget.insight;
  VoidCallback? get onDismiss => widget.onDismiss;
  Future<bool> Function(Uri uri)? get launcher => widget.launcher;
  TrustedContact? get contact => widget.contact;

  Future<void> _call(BuildContext context, TrustedContact target) async {
    final uri = Uri(scheme: 'tel', path: target.phone);
    var opened = false;
    try {
      opened =
          await (launcher ??
              (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      AppNotice.show(
        context,
        'Could not open the dialer. Call ${target.name} at ${target.phone}.',
        type: AppNoticeType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = contact ?? ref.watch(trustedContactProvider).valueOrNull;
    return GlassCard(
      key: const ValueKey('swap-watch-card'),
      accent: cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cyan.withValues(alpha: .15),
                  shape: BoxShape.circle,
                  border: Border.all(color: cyan.withValues(alpha: .7)),
                ),
                child: const Icon(
                  Icons.visibility_outlined,
                  color: cyan,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  insight.title,
                  key: const ValueKey('swap-watch-title'),
                  style: displayFont(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: cyan,
                    letterSpacing: .3,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  key: const ValueKey('swap-watch-dismiss'),
                  tooltip: 'Dismiss for a week',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 20, color: muted),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            insight.body,
            key: const ValueKey('swap-watch-body'),
            style: const TextStyle(fontSize: 14.5, height: 1.45),
          ),
          const SizedBox(height: 10),
          Text(
            insight.footer,
            key: const ValueKey('swap-watch-footer'),
            style: const TextStyle(color: muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (saved != null)
            FilledButton.icon(
              key: const ValueKey('swap-watch-call-sos'),
              onPressed: () => _call(context, saved),
              style: FilledButton.styleFrom(
                backgroundColor: cyan,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(44),
              ),
              icon: const Icon(Icons.call, size: 18),
              label: Text('CALL ${saved.name.toUpperCase()}'),
            )
          else
            const Text(
              'Add an SOS contact in Settings if you want a one-tap call, or talk to a doctor.',
              key: ValueKey('swap-watch-no-contact'),
              style: TextStyle(color: muted, fontSize: 12, height: 1.35),
            ),
        ],
      ),
    );
  }
}
