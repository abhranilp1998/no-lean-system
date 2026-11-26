import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../companion/presentation/companion_common.dart';
import '../../settings/services/trusted_contact_service.dart';
import '../domain/lower_tolerance.dart';

/// Full-screen lower-tolerance card shown after a qualifying slip is saved.
///
/// Contact-first: the only call button is the user's own SOS contact. There
/// is no government helpline and no Call 112 on this screen. A doctor or
/// hospital is mentioned as text only.
class LowerToleranceCard extends ConsumerWidget {
  const LowerToleranceCard({
    required this.warning,
    this.launcher,
    this.contact,
    this.onDismiss,
    super.key,
  });

  final ToleranceWarning warning;

  /// Test seam; defaults to the platform dialer.
  final Future<bool> Function(Uri uri)? launcher;

  /// Test seam; defaults to the saved trusted contact.
  final TrustedContact? contact;

  final VoidCallback? onDismiss;

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
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = contact ?? ref.watch(trustedContactProvider).valueOrNull;
    final accent = warning.isBenzoOnly ? toxic : Colors.amber;
    return SafeArea(
      child: Padding(
        key: const ValueKey('lower-tolerance-card'),
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .15),
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 1.5),
              ),
              child: Icon(Icons.favorite_outline, color: accent, size: 32),
            ),
            const SizedBox(height: 22),
            Text(
              warning.title,
              key: const ValueKey('tolerance-title'),
              style: displayFont(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: .4,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              warning.body,
              key: const ValueKey('tolerance-body'),
              style: const TextStyle(fontSize: 17, height: 1.45),
            ),
            const SizedBox(height: 14),
            Text(
              warning.footer,
              key: const ValueKey('tolerance-footer'),
              style: const TextStyle(color: muted, fontSize: 14, height: 1.4),
            ),
            const Spacer(),
            if (saved != null)
              FilledButton.icon(
                key: const ValueKey('tolerance-call-sos'),
                onPressed: () => _call(context, saved),
                style: FilledButton.styleFrom(
                  backgroundColor: cyan,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.call),
                label: Text('CALL ${saved.name.toUpperCase()}'),
              )
            else ...[
              FilledButton.icon(
                key: const ValueKey('tolerance-call-sos'),
                onPressed: null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.call),
                label: const Text('NO SOS CONTACT SAVED'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add an SOS contact in Settings, or call a doctor or hospital.',
                key: ValueKey('tolerance-no-contact'),
                style: TextStyle(color: muted, fontSize: 12, height: 1.35),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('tolerance-dismiss'),
              onPressed: onDismiss ?? () => Navigator.pop(context),
              child: const Text('GOT IT'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pushes the full-screen card. The caller waits until it is dismissed.
Future<void> showLowerToleranceCard(
  BuildContext context, {
  required ToleranceWarning warning,
  Future<bool> Function(Uri uri)? launcher,
  TrustedContact? contact,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      body: LowerToleranceCard(
        warning: warning,
        launcher: launcher,
        contact: contact,
      ),
    ),
  ),
);
