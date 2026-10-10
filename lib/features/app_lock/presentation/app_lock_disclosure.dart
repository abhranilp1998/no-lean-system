import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';

/// Prominent disclosure shown before sending the user to Android's
/// Usage access and "Display over other apps" screens. Nothing is granted
/// from here; it returns true only when the user taps continue.
class AppLockDisclosure extends StatelessWidget {
  const AppLockDisclosure({super.key});

  static Future<bool> open(BuildContext context) async =>
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AppLockDisclosure()),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    const points = [
      (
        Icons.query_stats,
        'What',
        'NO LEAN reads which app is on screen (Android "Usage access"), only to notice when an app you locked is opened.',
      ),
      (
        Icons.layers_outlined,
        'Why the second permission',
        '"Display over other apps" lets NO LEAN put its lock screen in front of a locked app. Android requires it for any app to open a screen from the background.',
      ),
      (
        Icons.lock_outline,
        'Where it goes',
        'Nowhere. Which apps you use is never stored, uploaded or shared. Only unlocks you choose ("I need this app") go on your own timeline.',
      ),
      (
        Icons.health_and_safety_outlined,
        'Always open',
        'Phone, emergency/SOS, maps, NO LEAN, settings and your home screen can never be locked. The lock screen always has SOS, Call 112, Go home and "I need this app".',
      ),
      (
        Icons.toggle_off_outlined,
        'Turning it off',
        'Switch app lock off in Settings (your PIN if you set one), or revoke Usage access in Android settings at any time. Nothing stays locked.',
      ),
    ];
    return Scaffold(
      key: const ValueKey('app-lock-disclosure'),
      appBar: AppBar(
        title: Text(
          'USAGE ACCESS',
          style: displayFont(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          children: [
            const Text(
              'Lock the apps you use to buy or arrange it, during your risk window or inside danger zones.',
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
              'Android opens its settings page next. Find NO LEAN and switch it on, then come back.',
              style: TextStyle(color: muted, fontSize: 11.5, height: 1.45),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('app-lock-disclosure-continue'),
              style: FilledButton.styleFrom(backgroundColor: magenta),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.shield_outlined),
              label: const Text('CONTINUE TO ANDROID SETTINGS'),
            ),
            const SizedBox(height: 10),
            TextButton(
              key: const ValueKey('app-lock-disclosure-not-now'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('NOT NOW'),
            ),
          ],
        ),
      ),
    );
  }
}
