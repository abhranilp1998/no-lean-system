import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';

class AnimatedBackground extends StatelessWidget {
  const AnimatedBackground({
    required this.risk,
    required this.scanlines,
    super.key,
  });

  final bool risk;
  final bool scanlines;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _BackgroundPainter(
            risk: risk,
            scanlines: scanlines && !visuals.reduceMotion,
            visuals: visuals,
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
  });

  final bool risk;
  final bool scanlines;
  final NoLeanVisuals visuals;

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

    final glow = Paint()
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        100 * visuals.glowRadiusScale,
      );
    glow.color = (risk ? red : cyan).withValues(
      alpha: visuals.glowOpacity(.08),
    );
    canvas.drawCircle(Offset(size.width * .75, size.height * .12), 170, glow);
    glow.color = purple.withValues(alpha: visuals.glowOpacity(.06));
    canvas.drawCircle(Offset(size.width * .15, size.height * .78), 210, glow);

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
  }

  void _paintChromaticGlitches(Canvas canvas, Size size) {
    if (visuals.reduceMotion || visuals.effectScale < .5) return;
    final glitchCount = (visuals.effectScale * 4).round().clamp(2, 7);
    for (var index = 0; index < glitchCount; index++) {
      final y = ((index * 149.0) + size.height * .17) % size.height;
      final width = size.width * (.14 + (index % 3) * .09);
      final x = ((index * 83.0) + size.width * .08) % size.width;
      final accent = index.isEven ? cyan : magenta;
      final paint = Paint()
        ..color = accent.withValues(alpha: visuals.glowOpacity(.025));
      canvas.drawRect(
        Rect.fromLTWH(x - width * .5, y, width, index.isEven ? 1 : .65),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) =>
      oldDelegate.risk != risk ||
      oldDelegate.scanlines != scanlines ||
      oldDelegate.visuals.highContrast != visuals.highContrast ||
      oldDelegate.visuals.reduceMotion != visuals.reduceMotion ||
      oldDelegate.visuals.effectScale != visuals.effectScale;
}
