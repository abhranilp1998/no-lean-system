import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({
    required this.risk,
    required this.scanlines,
    super.key,
  });

  final bool risk;
  final bool scanlines;

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visuals = NoLeanVisuals.of(context);
    _controller.duration = visuals.ultraMode
        ? const Duration(milliseconds: 2800)
        : const Duration(seconds: 6);
    final shouldAnimate = !visuals.reduceMotion && visuals.effectScale >= 1.3;
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
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
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, child) => CustomPaint(
              painter: _BackgroundPainter(
                risk: widget.risk,
                scanlines: widget.scanlines && !visuals.reduceMotion,
                visuals: visuals,
                phase: _controller.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({
    required this.risk,
    required this.scanlines,
    required this.visuals,
    required this.phase,
  });

  final bool risk;
  final bool scanlines;
  final NoLeanVisuals visuals;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: visuals.highContrast
          ? risk
                ? [
                    Colors.black,
                    const Color(0xFF250616),
                    const Color(0xFF050008),
                  ]
                : [
                    Colors.black,
                    const Color(0xFF031126),
                    const Color(0xFF150024),
                  ]
          : risk
          ? [ink, const Color(0xFF190B16), const Color(0xFF090811)]
          : [ink, const Color(0xFF080D19), const Color(0xFF110A1D)],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

    final pulse = visuals.reduceMotion
        ? 1.0
        : 1 + math.sin(phase * math.pi * 2) * (visuals.ultraMode ? .13 : .06);
    final glow = Paint()
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        100 * visuals.glowRadiusScale * pulse,
      );
    glow.color = (risk ? red : cyan).withValues(
      alpha: visuals.glowOpacity(.08),
    );
    final drift = visuals.reduceMotion
        ? Offset.zero
        : Offset(
            math.sin(phase * math.pi * 2) * 18 * visuals.effectScale,
            math.cos(phase * math.pi * 2) * 12 * visuals.effectScale,
          );
    canvas.drawCircle(
      Offset(size.width * .75, size.height * .12) + drift,
      170,
      glow,
    );
    glow.color = purple.withValues(alpha: visuals.glowOpacity(.06));
    canvas.drawCircle(
      Offset(size.width * .15, size.height * .78) - drift,
      210,
      glow,
    );

    final grid = Paint()
      ..color = Colors.white.withValues(
        alpha: visuals.accentOpacity(
          .025,
          minimum: visuals.highContrast ? .026 : 0,
        ),
      )
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (scanlines) {
      final line = Paint()
        ..color = Colors.white.withValues(alpha: visuals.accentOpacity(.018));
      for (var y = 0.0; y < size.height; y += 5) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
      }
    }

    _paintChromaticGlitches(canvas, size);
    _paintGlyphField(canvas, size);
  }

  void _paintChromaticGlitches(Canvas canvas, Size size) {
    if (visuals.reduceMotion || visuals.effectScale < .5) return;
    final glitchCount = (visuals.effectScale * 5).round().clamp(2, 14);
    for (var index = 0; index < glitchCount; index++) {
      final phaseShift = phase * size.height * (visuals.ultraMode ? .72 : .24);
      final y =
          ((index * 149.0) + size.height * .17 + phaseShift) % size.height;
      final width =
          size.width *
          (.14 + (index % 3) * .09) *
          (visuals.ultraMode ? 1.32 : 1);
      final x = ((index * 83.0) + size.width * .08 + phase * 37) % size.width;
      final accent = index.isEven ? cyan : magenta;
      final paint = Paint()
        ..color = accent.withValues(
          alpha: visuals.glowOpacity(visuals.ultraMode ? .075 : .025),
        );
      canvas.drawRect(
        Rect.fromLTWH(
          x - width * .5,
          y,
          width,
          (index.isEven ? 1.2 : .75) * (visuals.ultraMode ? 2 : 1),
        ),
        paint,
      );
      if (visuals.ultraMode && index % 3 == 0) {
        canvas.drawRect(
          Rect.fromLTWH(x - width * .5 - 5, y + 3, width * .72, 1),
          Paint()..color = magenta.withValues(alpha: visuals.glowOpacity(.055)),
        );
      }
    }
  }

  void _paintGlyphField(Canvas canvas, Size size) {
    if (visuals.reduceMotion || visuals.effectScale < 1.3) return;
    const glyphs = ['//', '0x', '<>', '::', '01', '[]', '##', '+'];
    final count = visuals.ultraMode ? 24 : 9;
    for (var index = 0; index < count; index++) {
      final lane = index % 6;
      final travel = phase * size.height * (18 + lane * 3);
      final x = ((index * 71.0) + lane * 19) % size.width;
      final y = ((index * 113.0) + travel + size.height * .05) % size.height;
      final color = index % 3 == 0
          ? magenta
          : index.isEven
          ? cyan
          : toxic;
      final painter = TextPainter(
        text: TextSpan(
          text: glyphs[index % glyphs.length],
          style: TextStyle(
            color: color.withValues(
              alpha: visuals.glowOpacity(visuals.ultraMode ? .14 : .045),
            ),
            fontFamily: 'NoLeanMono',
            fontSize: visuals.ultraMode ? 11 + (index % 3) * 2 : 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) =>
      oldDelegate.risk != risk ||
      oldDelegate.scanlines != scanlines ||
      oldDelegate.visuals.highContrast != visuals.highContrast ||
      oldDelegate.visuals.reduceMotion != visuals.reduceMotion ||
      oldDelegate.visuals.effectScale != visuals.effectScale ||
      oldDelegate.phase != phase;
}
