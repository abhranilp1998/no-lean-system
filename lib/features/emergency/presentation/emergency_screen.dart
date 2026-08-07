import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/status_pill.dart';
import '../../recovery/application/recovery_provider.dart';

class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key});

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  Timer? _timer;
  int _remaining = 60;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        setState(() {
          _remaining = 0;
          _finished = true;
        });
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final phase = _remaining > 45
        ? 'BREATHE IN'
        : _remaining > 30
        ? 'HOLD THE LINE'
        : _remaining > 15
        ? 'BREATHE OUT'
        : 'LET THE WAVE PASS';
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _SosPainter(_remaining)),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.close, color: Colors.transparent),
                    ),
                    const Spacer(),
                    const StatusPill(label: 'SYSTEM OVERRIDE', color: red),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: red),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'SOS MODE',
                  textAlign: TextAlign.center,
                  style: displayFont(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: red,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'DO NOT BUY. DO NOT DRIVE. STAY HERE.',
                  textAlign: TextAlign.center,
                  style: microStyle.copyWith(
                    color: Colors.white70,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  height: 246,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: _remaining / 60,
                          strokeWidth: 7,
                          color: red,
                          backgroundColor: red.withValues(alpha: .12),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$_remaining',
                            style: displayFont(
                              fontSize: 70,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'SECONDS',
                            style: microStyle.copyWith(color: red),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  phase,
                  textAlign: TextAlign.center,
                  style: displayFont(
                    fontSize: 15,
                    color: red,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 30),
                GlassCard(
                  accent: red,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WHY YOU ARE DONE WITH THIS',
                        style: microStyle.copyWith(color: red),
                      ),
                      const SizedBox(height: 12),
                      if (recovery.reasons.isEmpty)
                        const Text(
                          'No reasons saved yet. Add them in Settings before the next risk window.',
                          style: TextStyle(
                            fontSize: 12,
                            color: muted,
                            height: 1.35,
                          ),
                        )
                      else
                        ...recovery.reasons.map(
                          (reason) => Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '—',
                                  style: TextStyle(
                                    color: red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (!_finished)
                  const Text(
                    'The urge peaks, then drops. Give it the minute it is asking for.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 11, height: 1.4),
                  ),
                if (_finished) ...[
                  const Text(
                    'You stayed for the wave. Lock in the next decision before you leave.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: toxic,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlowButton(
                    label: 'I WILL NOT BUY LEAN TODAY',
                    icon: Icons.lock_outline,
                    color: toxic,
                    onTap: () async {
                      await ref.read(recoveryProvider).pledge();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SosPainter extends CustomPainter {
  _SosPainter(this.remaining);

  final int remaining;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = .06 + (remaining % 2) * .03;
    final paint = Paint()
      ..color = red.withValues(alpha: pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    canvas.drawCircle(Offset(size.width / 2, 260), 160, paint);
    final line = Paint()
      ..color = red.withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 7) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _SosPainter oldDelegate) =>
      oldDelegate.remaining != remaining;
}
