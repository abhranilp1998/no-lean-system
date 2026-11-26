import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../companion/presentation/companion_common.dart';
import '../../settings/services/trusted_contact_service.dart';
import '../domain/mixing_alert.dart';
import '../domain/mixing_safety_net.dart';

/// Bundled illustration: lying on their side, top knee bent, hand under the
/// cheek, head tilted back.
const recoveryPositionAsset = 'assets/recovery_position.png';

/// Calm full-screen safety card shown after a save that leaves a codeine +
/// benzo/alcohol mix in the log. It quotes the user's own log, says what to
/// do tonight, and puts their own SOS contact first. It never lists a public
/// helpline or emergency number: the next steps are a person they know, a
/// doctor, or a hospital.
class MixingAlertScreen extends ConsumerWidget {
  const MixingAlertScreen({
    required this.alert,
    this.contact,
    this.launcher,
    super.key,
  });

  final MixingAlert alert;

  /// Test seam; defaults to the saved trusted contact.
  final TrustedContact? contact;

  /// Test seam; defaults to the platform (tel:/sms:) launcher.
  final Future<bool> Function(Uri uri)? launcher;

  /// Pushes the card full-screen. Resolves when it is closed.
  static Future<void> show(
    BuildContext context,
    MixingAlert alert, {
    TrustedContact? contact,
    Future<bool> Function(Uri uri)? launcher,
  }) => Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          MixingAlertScreen(alert: alert, contact: contact, launcher: launcher),
    ),
  );

  Future<void> _open(BuildContext context, Uri uri, String failure) async {
    bool opened;
    try {
      opened =
          await (launcher ??
              (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      AppNotice.show(context, failure, type: AppNoticeType.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = contact ?? ref.watch(trustedContactProvider).valueOrNull;
    final name = saved?.name.trim();
    final phone = saved?.phone ?? '';
    final who = (name == null || name.isEmpty) ? null : name.toUpperCase();
    const body = TextStyle(fontSize: 14, height: 1.5);

    return Scaffold(
      key: const ValueKey('mixing-alert'),
      backgroundColor: ink,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                children: [
                  Row(
                    children: [
                      const Icon(Icons.health_and_safety_outlined, color: cyan),
                      const SizedBox(width: 8),
                      Text(
                        'SAFETY CHECK',
                        style: eyebrowStyle.copyWith(color: cyan),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    alert.quote,
                    key: const ValueKey('mixing-alert-quote'),
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Together they can slow your breathing much more than '
                    'either one alone. It can build up quietly, and sleep '
                    'makes it worse. Nothing wrong with you for being here; '
                    'this is just the safest way through tonight.',
                    style: body,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'TONIGHT',
                    style: eyebrowStyle.copyWith(color: Colors.amber),
                  ),
                  const SizedBox(height: 8),
                  const _Step(
                    key: ValueKey('mixing-step-alone'),
                    text: "Don't use alone tonight.",
                  ),
                  const _Step(
                    key: ValueKey('mixing-step-more'),
                    text: "Don't take more of either for the next few hours.",
                  ),
                  const _Step(
                    text:
                        'Tell someone where you are and keep your phone '
                        'next to you.',
                  ),
                  const _Step(
                    text: 'If you feel very drowsy, lie on your side.',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'IF BREATHING IS SLOW, OR THEY CAN\'T BE WOKEN',
                    style: eyebrowStyle.copyWith(color: red),
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    label:
                        'Recovery position: lying on the side, top knee '
                        'bent, hand under the cheek, head tilted back.',
                    image: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        recoveryPositionAsset,
                        key: const ValueKey('recovery-position-image'),
                        fit: BoxFit.fitWidth,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Roll them onto their side: top knee bent, hand under '
                    'the cheek, head tilted back so the airway stays open. '
                    'Stay with them and get them to a hospital now.',
                    style: body,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('mixing-call-contact'),
                    onPressed: () => _open(
                      context,
                      Uri(scheme: 'tel', path: phone),
                      'COULD NOT OPEN THE DIALER // CALL SOMEONE YOU TRUST.',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: cyan,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(60),
                      textStyle: const TextStyle(
                        fontFamily: 'NoLeanMono',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    icon: const Icon(Icons.call),
                    label: Text(
                      who == null ? 'CALL SOMEONE I TRUST' : 'CALL $who',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('mixing-text-contact'),
                    onPressed: () => _open(
                      context,
                      Uri(
                        scheme: 'sms',
                        path: phone,
                        queryParameters: {'body': mixingPingText},
                      ),
                      'COULD NOT OPEN MESSAGES // TEXT SOMEONE YOU TRUST.',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cyan,
                      side: const BorderSide(color: cyan),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.sms_outlined),
                    label: Text(
                      who == null ? 'TEXT SOMEONE I TRUST' : 'TEXT $who',
                    ),
                  ),
                  if (who == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'No SOS contact saved yet (Settings > Trusted '
                        'contact). Pick someone you trust.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('mixing-alert-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("I'VE READ THIS"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2, right: 10),
          child: Icon(Icons.circle, size: 8, color: Colors.amber),
        ),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4)),
        ),
      ],
    ),
  );
}
