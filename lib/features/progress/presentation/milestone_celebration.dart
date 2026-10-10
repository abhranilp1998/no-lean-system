import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/no_lean_visuals.dart';
import '../../recovery/domain/milestones.dart';

/// Full-screen milestone celebration. Reduce motion shows the same card with
/// no movement: static rings, no glitch, no scan sweep, instant transitions.
Future<void> showMilestoneCelebration(
  BuildContext context, {
  required int days,
}) {
  final reduceMotion = NoLeanVisuals.of(context).reduceMotion;
  AppFeedback.success();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .86),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => MilestoneCelebration(days: days),
    transitionBuilder: (_, animation, _, child) => reduceMotion
        ? child
        : FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: .92, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          ),
  );
}

class MilestoneCelebration extends StatefulWidget {
  const MilestoneCelebration({required this.days, super.key});

  final int days;

  @override
  State<MilestoneCelebration> createState() => _MilestoneCelebrationState();
}

class _MilestoneCelebrationState extends State<MilestoneCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (NoLeanVisuals.of(context).reduceMotion) {
      _controller.value = 1;
    } else {
      // One burst, then a slow idle pulse.
      _controller.forward().whenComplete(() {
        if (mounted) _controller.repeat(min: .55, max: 1, reverse: true);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    final milestone = milestoneFor(widget.days);
    final label = milestone?.label ?? 'MILESTONE';
    final color = widget.days >= 30 ? toxic : cyan;
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              final glitch = visuals.reduceMotion
                  ? 0.0
                  : math.sin(t * math.pi * 14) * 2.4 * visuals.effectScale;
              return Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    height: 320,
                    child: CustomPaint(
                      key: const ValueKey('milestone-burst'),
                      painter: MilestoneBurstPainter(
                        progress: t,
                        color: color,
                        accent: magenta,
                        animated: !visuals.reduceMotion,
                        glow: visuals.glowOpacity(.5),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'MILESTONE UNLOCKED',
                        style: eyebrowStyle.copyWith(color: color),
                      ),
                      const SizedBox(height: 8),
                      Stack(
                        children: [
                          if (glitch != 0) ...[
                            Transform.translate(
                              offset: Offset(-glitch, 0),
                              child: _daysText(magenta.withValues(alpha: .7)),
                            ),
                            Transform.translate(
                              offset: Offset(glitch, 0),
                              child: _daysText(cyan.withValues(alpha: .7)),
                            ),
                          ],
                          _daysText(Colors.white),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        key: const ValueKey('milestone-label'),
                        style: displayFont(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.days} days clean. Logged in your timeline.',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        key: const ValueKey('milestone-dismiss'),
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(backgroundColor: color),
                        child: const Text(
                          'KEEP GOING',
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _daysText(Color color) => Text(
    '${widget.days}D',
    style: displayFont(fontSize: 64, fontWeight: FontWeight.w700, color: color),
  );
}

/// Expanding neon rings, radial ticks and a scan sweep.
class MilestoneBurstPainter extends CustomPainter {
  const MilestoneBurstPainter({
    required this.progress,
    required this.color,
    required this.accent,
    required this.animated,
    required this.glow,
  });

  final double progress;
  final Color color;
  final Color accent;
  final bool animated;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < 3; i++) {
      final phase = animated ? ((progress + i / 3) % 1) : (i + 1) / 3.6;
      ring.color = (i.isEven ? color : accent).withValues(
        alpha: (1 - phase) * glow,
      );
      canvas.drawCircle(center, maxRadius * (.35 + .65 * phase), ring);
    }
    final tick = Paint()
      ..color = color.withValues(alpha: .55 * glow + .2)
      ..strokeWidth = 2;
    const ticks = 24;
    final spin = animated ? progress * math.pi / 6 : 0.0;
    for (var i = 0; i < ticks; i++) {
      final angle = spin + i * 2 * math.pi / ticks;
      final inner = maxRadius * (i.isEven ? .78 : .84);
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + dir * inner,
        center + dir * maxRadius * .9,
        tick,
      );
    }
    if (animated && progress < 1) {
      final y = size.height * progress;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, 2),
        Paint()..color = color.withValues(alpha: .35 * glow),
      );
    }
  }

  @override
  bool shouldRepaint(MilestoneBurstPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.animated != animated ||
      old.glow != glow;
}
