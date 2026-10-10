import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_provider.dart';
import '../services/location_service.dart';

/// Prominent disclosure shown before asking for background location.
/// Nothing is requested until the user taps the allow button.
class BackgroundGeofenceDisclosure extends ConsumerStatefulWidget {
  const BackgroundGeofenceDisclosure({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const BackgroundGeofenceDisclosure()),
  );

  @override
  ConsumerState<BackgroundGeofenceDisclosure> createState() =>
      _BackgroundGeofenceDisclosureState();
}

class _BackgroundGeofenceDisclosureState
    extends ConsumerState<BackgroundGeofenceDisclosure> {
  bool _busy = false;
  bool _needsSettings = false;

  Future<void> _allow() async {
    setState(() => _busy = true);
    try {
      final location = ref.read(locationServiceProvider);
      final access = await location.requestBackground();
      if (!mounted) return;
      if (access == LocationAccess.always) {
        await ref.read(recoveryProvider).setBackgroundGeofencing(true);
        if (!mounted) return;
        AppNotice.show(
          context,
          'BACKGROUND ZONE ALERTS ON. Turn them off any time in Danger Zones.',
          type: AppNoticeType.success,
        );
        Navigator.pop(context);
        return;
      }
      setState(() => _needsSettings = true);
      AppNotice.show(context, switch (access) {
        LocationAccess.serviceDisabled =>
          'Device location is off. Turn it on, then try again.',
        LocationAccess.whileInUse =>
          'Android granted "while in use" only. Background alerts need "Allow all the time".',
        _ => 'Location was not granted. Background alerts stay off.',
      }, type: AppNoticeType.warning);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const points = [
      (
        Icons.place_outlined,
        'What',
        'NO LEAN uses your location in the background, even when the app is closed, only to detect when you enter a danger zone you marked.',
      ),
      (
        Icons.battery_saver_outlined,
        'How',
        'Android geofencing watches your zones. There is no continuous GPS tracking and no location history is stored.',
      ),
      (
        Icons.lock_outline,
        'Where it goes',
        'Nowhere. Zones and alerts stay on this device. Nothing is uploaded or shared.',
      ),
      (
        Icons.toggle_off_outlined,
        'Turning it off',
        'One switch in Danger Zones, no PIN required. You can also revoke location in Android settings.',
      ),
    ];
    return Scaffold(
      key: const ValueKey('geofence-disclosure'),
      appBar: AppBar(
        title: Text(
          'BACKGROUND LOCATION',
          style: displayFont(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          children: [
            const Text(
              'Get an alert the moment you walk into a danger zone, even with the app closed.',
              style: TextStyle(fontSize: 15, height: 1.45),
            ),
            const SizedBox(height: 16),
            for (final (icon, title, body) in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  accent: cyan,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: cyan, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.toUpperCase(),
                              style: eyebrowStyle.copyWith(color: cyan),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              body,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            const Text(
              'Android will ask for location twice: first "while using the app", then "Allow all the time" (on newer Android this opens a settings page).',
              style: TextStyle(color: muted, fontSize: 11.5, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('geofence-allow'),
              style: FilledButton.styleFrom(backgroundColor: red),
              onPressed: _busy ? null : _allow,
              icon: const Icon(Icons.shield_outlined),
              label: Text(
                _busy ? 'WAITING FOR ANDROID…' : 'CONTINUE TO PERMISSION',
              ),
            ),
            if (_needsSettings) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('geofence-settings'),
                onPressed: () =>
                    ref.read(locationServiceProvider).openSettings(),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('OPEN APP SETTINGS'),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              key: const ValueKey('geofence-not-now'),
              onPressed: () => Navigator.pop(context),
              child: const Text('NOT NOW'),
            ),
          ],
        ),
      ),
    );
  }
}
