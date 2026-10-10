import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/dose_safety.dart';

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

/// Overdose signs and first steps, with a one-tap 112 call. Shown whenever
/// a logging warning fires.
class OverdoseSignsCard extends StatelessWidget {
  const OverdoseSignsCard({this.launcher, super.key});

  /// Test seam; defaults to the platform dialer.
  final Future<bool> Function(Uri uri)? launcher;

  static const signs = [
    'Cannot be woken, or will not respond to their name',
    'Slow, shallow or stopped breathing; snoring or gurgling',
    'Blue or grey lips and fingertips',
    'Tiny pinpoint pupils, limp body',
  ];

  static const steps = [
    'Call $emergencyNumber now. Say "not breathing properly".',
    'Lay them on their side so they cannot choke.',
    'Give naloxone if you have it. Stay until help arrives.',
  ];

  Future<void> _call(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: emergencyNumber);
    try {
      final opened =
          await (launcher ??
              (uri) =>
                  launchUrl(uri, mode: LaunchMode.externalApplication))(uri);
      if (!opened && context.mounted) {
        AppNotice.show(
          context,
          'NO DIALER AVAILABLE // CALL $emergencyNumber MANUALLY.',
          type: AppNoticeType.error,
        );
      }
    } catch (_) {
      if (context.mounted) {
        AppNotice.show(
          context,
          'COULD NOT OPEN DIALER // CALL $emergencyNumber MANUALLY.',
          type: AppNoticeType.error,
        );
      }
    }
  }

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
          FilledButton.icon(
            key: const ValueKey('call-112'),
            onPressed: () => _call(context),
            style: FilledButton.styleFrom(
              backgroundColor: red,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.call),
            label: const Text('CALL $emergencyNumber'),
          ),
        ],
      ),
    );
  }
}
