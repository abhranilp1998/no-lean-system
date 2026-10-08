import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../settings/presentation/widgets/settings_controls.dart';
import '../services/location_service.dart';

/// Opt-in location controls. Turning either switch off is always one tap.
class ZoneMonitoringPanel extends ConsumerWidget {
  const ZoneMonitoringPanel({super.key});

  Future<void> _setInApp(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final recovery = ref.read(recoveryProvider);
    if (!enabled) {
      await recovery.setZoneMonitoring(false);
      return;
    }
    final access = await ref.read(locationServiceProvider).requestForeground();
    if (!context.mounted) return;
    if (access == LocationAccess.whileInUse ||
        access == LocationAccess.always) {
      await recovery.setZoneMonitoring(true);
      return;
    }
    AppNotice.show(
      context,
      access == LocationAccess.serviceDisabled
          ? 'Turn device location on to use in-app zone alerts.'
          : 'Location was not granted, so in-app zone alerts stay off.',
      type: AppNoticeType.warning,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ZONE ALERTS', style: eyebrowStyle.copyWith(color: magenta)),
        const SizedBox(height: 8),
        SettingToggle(
          key: const ValueKey('zone-monitoring-toggle'),
          title: 'Alert while NO LEAN is open',
          subtitle:
              'Checks distance only while the app is on screen // 50 m steps',
          value: recovery.zoneMonitoring,
          color: magenta,
          onChanged: (value) => _setInApp(context, ref, value),
        ),
      ],
    );
  }
}
