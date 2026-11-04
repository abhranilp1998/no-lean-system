import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../companion/presentation/companion_common.dart';
import '../../settings/services/trusted_contact_service.dart';
import '../domain/dose_safety.dart';
import '../domain/mixing_safety_net.dart';

/// India's single emergency number.
const emergencyNumber = '112';

class DoseWarningCard extends StatelessWidget {
  const DoseWarningCard({required this.warning, super.key});

  final DoseWarning warning;

  @override
  Widget build(BuildContext context) {
    final color = warning.kind == DoseWarningKind.tolerance
        ? Colors.amber
        : red;
    return Semantics(
      container: true,
      label: '${warning.title}. ${warning.body}',
      child: Container(
        key: ValueKey('dose-warning-${warning.kind.name}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1.5),
        ),
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.report_gmailerrorred, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      warning.title,
                      style: eyebrowStyle.copyWith(color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      warning.body,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// (B) Contact first: "Ping my SOS contact now" is the big button. 112 is
/// behind a second tap (reveal, then call), and only when the setting allows.
class MixingSafetyNetCard extends ConsumerStatefulWidget {
  const MixingSafetyNetCard({this.launcher, this.contact, super.key});

  /// Test seam; defaults to the platform (sms:/tel:) launcher.
  final Future<bool> Function(Uri uri)? launcher;

  /// Test seam; defaults to the saved trusted contact.
  final TrustedContact? contact;

  @override
  ConsumerState<MixingSafetyNetCard> createState() =>
      _MixingSafetyNetCardState();
}

class _MixingSafetyNetCardState extends ConsumerState<MixingSafetyNetCard> {
  bool _show112 = false;

  Future<void> _open(Uri uri, String failure) async {
    bool opened;
    try {
      opened =
          await (widget.launcher ??
              (uri) =>
                  launchUrl(uri, mode: LaunchMode.externalApplication))(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      AppNotice.show(context, failure, type: AppNoticeType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final net =
        ref.watch(mixingSafetyNetProvider).valueOrNull ??
        defaultMixingSafetyNet;
    if (!net.showsContact) return const SizedBox.shrink();
    final contact =
        widget.contact ?? ref.watch(trustedContactProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('mixing-ping-contact'),
          onPressed: () => _open(
            Uri(
              scheme: 'sms',
              path: contact?.phone ?? '',
              queryParameters: {'body': mixingPingText},
            ),
            'COULD NOT OPEN MESSAGES // TEXT SOMEONE YOU TRUST.',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: cyan,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.sms_outlined),
          label: Text(
            contact == null
                ? 'PING SOMEONE NOW'
                : 'PING ${contact.name.toUpperCase()} NOW',
          ),
        ),
        if (contact == null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'No SOS contact saved (Settings > Trusted contact). You can pick who to text.',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ),
        if (net.shows112) ...[
          const SizedBox(height: 6),
          if (!_show112)
            TextButton(
              key: const ValueKey('mixing-reveal-112'),
              onPressed: () => setState(() => _show112 = true),
              child: const Text('NOT BREATHING RIGHT? EMERGENCY OPTIONS'),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('call-112'),
              onPressed: () => _open(
                Uri(scheme: 'tel', path: emergencyNumber),
                'COULD NOT OPEN DIALER // CALL $emergencyNumber MANUALLY.',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: red,
                side: const BorderSide(color: red),
                minimumSize: const Size.fromHeight(44),
              ),
              icon: const Icon(Icons.call),
              label: const Text('CALL $emergencyNumber NOW'),
            ),
        ],
      ],
    );
  }
}

/// Overdose signs and first steps, with a one-tap 112 call. Shown whenever
/// a logging warning fires.
class OverdoseSignsCard extends StatelessWidget {
  const OverdoseSignsCard({this.launcher, this.contact, super.key});

  /// Test seam; defaults to the platform dialer.
  final Future<bool> Function(Uri uri)? launcher;

  /// Test seam; defaults to the saved trusted contact.
  final TrustedContact? contact;

  static const signs = [
    'Cannot be woken, or will not respond to their name',
    'Slow, shallow or stopped breathing; snoring or gurgling',
    'Blue or grey lips and fingertips',
    'Tiny pinpoint pupils, limp body',
  ];

  static const steps = [
    'Ping your SOS contact now. If breathing is slow or stopped, call $emergencyNumber.',
    'Lay them on their side so they cannot choke.',
    'Give naloxone if you have it. Stay until help arrives.',
  ];

  @override
  Widget build(BuildContext context) {
    TextStyle line = const TextStyle(fontSize: 12, height: 1.4);
    return Container(
      key: const ValueKey('overdose-signs-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: red, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OVERDOSE SIGNS', style: eyebrowStyle.copyWith(color: red)),
          const SizedBox(height: 6),
          for (final sign in signs) Text('• $sign', style: line),
          const SizedBox(height: 8),
          Text('DO THIS', style: eyebrowStyle.copyWith(color: Colors.amber)),
          const SizedBox(height: 4),
          for (var i = 0; i < steps.length; i++)
            Text('${i + 1}. ${steps[i]}', style: line),
          const SizedBox(height: 10),
          MixingSafetyNetCard(launcher: launcher, contact: contact),
        ],
      ),
    );
  }
}
