import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _BackgroundPainter(risk: risk, scanlines: scanlines),
        ),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter({required this.risk, required this.scanlines});

  final bool risk;
  final bool scanlines;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: risk
          ? [ink, const Color(0xFF190B16), const Color(0xFF090811)]
          : [ink, const Color(0xFF080D19), const Color(0xFF110A1D)],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);
    glow.color = (risk ? red : cyan).withValues(alpha: .08);
    canvas.drawCircle(Offset(size.width * .75, size.height * .12), 170, glow);
    glow.color = purple.withValues(alpha: .06);
    canvas.drawCircle(Offset(size.width * .15, size.height * .78), 210, glow);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (scanlines) {
      final line = Paint()..color = Colors.white.withValues(alpha: .018);
      for (var y = 0.0; y < size.height; y += 5) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) =>
      oldDelegate.risk != risk || oldDelegate.scanlines != scanlines;
}
