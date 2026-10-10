import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/zone_alert_copy.dart';

enum ZoneAlertChoice { sos, craving, exit }

/// Full-screen in-app interrupt on zone entry. Never traps the user: the
/// close button, system back and "I'M LEAVING" all exit in one tap.
class ZoneAlertScreen extends StatelessWidget {
  const ZoneAlertScreen({required this.copy, super.key});

  final ZoneAlertCopy copy;

  static Future<ZoneAlertChoice?> show(
    BuildContext context,
    ZoneAlertCopy copy,
  ) => Navigator.of(context).push<ZoneAlertChoice>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ZoneAlertScreen(copy: copy),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('zone-alert-screen'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            key: const ValueKey('zone-alert-close'),
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, ZoneAlertChoice.exit),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(label: 'ZONE ENTERED', color: red),
            ),
            const SizedBox(height: 16),
            Text(
              copy.title,
              style: displayFont(
                color: red,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Text(copy.body, style: const TextStyle(fontSize: 14, height: 1.5)),
            const SizedBox(height: 28),
            GlowButton(
              key: const ValueKey('zone-alert-sos'),
              label: 'OPEN SOS',
              icon: Icons.emergency_outlined,
              color: red,
              onTap: () => Navigator.pop(context, ZoneAlertChoice.sos),
            ),
            const SizedBox(height: 12),
            GlowButton(
              key: const ValueKey('zone-alert-craving'),
              label: 'LOG CRAVING',
              icon: Icons.bolt,
              color: cyan,
              onTap: () => Navigator.pop(context, ZoneAlertChoice.craving),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('zone-alert-exit'),
              onPressed: () => Navigator.pop(context, ZoneAlertChoice.exit),
              icon: const Icon(Icons.directions_walk, color: toxic),
              label: const Text('I\'M LEAVING // EXIT'),
            ),
          ],
        ),
      ),
    );
  }
}
