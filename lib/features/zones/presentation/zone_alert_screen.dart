import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/zone_alert_copy.dart';

enum ZoneAlertChoice { sos, craving, exit }

/// Full-screen in-app interrupt on zone entry. Never traps the user: the
/// close button, system back and "I'M LEAVING" all exit in one tap.
/// Plan P0-3: a 10-minute "ride it out" timer runs at the top, since a
/// craving usually peaks and drops within that window.
class ZoneAlertScreen extends StatefulWidget {
  const ZoneAlertScreen({required this.copy, super.key});

  final ZoneAlertCopy copy;

  static const holdFor = Duration(minutes: 10);

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
  State<ZoneAlertScreen> createState() => _ZoneAlertScreenState();
}

/// mm:ss for the hold timer.
String formatHold(Duration left) {
  final s = left.inSeconds.clamp(0, 99 * 60);
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

class _ZoneAlertScreenState extends State<ZoneAlertScreen> {
  late final DateTime _start = DateTime.now();
  Timer? _timer;
  Duration _left = ZoneAlertScreen.holdFor;

  ZoneAlertCopy get copy => widget.copy;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = ZoneAlertScreen.holdFor - DateTime.now().difference(_start);
      setState(() => _left = left.isNegative ? Duration.zero : left);
      if (left.isNegative) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _left == Duration.zero;
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
            const SizedBox(height: 20),
            Container(
              key: const ValueKey('zone-alert-timer'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (done ? toxic : red).withValues(alpha: .6),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    done ? 'YOU HELD ON 10 MINUTES' : 'GIVE IT 10 MINUTES',
                    style: TextStyle(
                      color: done ? toxic : red,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatHold(_left),
                    style: displayFont(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    done
                        ? 'That wave is usually past its peak now. Keep walking away. I\'ll check in on you soon.'
                        : 'Walk away while this runs. Don\'t decide anything until it hits zero.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
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
