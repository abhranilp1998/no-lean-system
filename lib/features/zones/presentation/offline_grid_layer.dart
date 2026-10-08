import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/danger_zone.dart';

/// Offline map layer: a dark coordinate grid with a metric scale bar. Drawn
/// under the street tiles as the no-network fallback, and again faintly on top
/// (no background) so the HUD grid and scale bar stay visible over tiles.
class OfflineGridLayer extends StatelessWidget {
  const OfflineGridLayer({
    this.background = true,
    this.showScaleBar = true,
    this.lineOpacity = 1,
    super.key,
  });

  final bool background;
  final bool showScaleBar;
  final double lineOpacity;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GridPainter(
          camera,
          background: background,
          showScaleBar: showScaleBar,
          lineOpacity: lineOpacity,
        ),
      ),
    );
  }
}

/// Picks a grid step (degrees) so lines land roughly every 90+ pixels.
double gridStepDegrees(double pixelsPerDegree) {
  const steps = [
    20.0, 10.0, 5.0, 2.0, 1.0, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01, //
    0.005, 0.002, 0.001, 0.0005, 0.0002, 0.0001,
  ];
  for (final step in steps.reversed) {
    if (step * pixelsPerDegree >= 90) return step;
  }
  return steps.first;
}

/// Rounds a distance to a readable scale-bar length in metres.
double niceScaleMeters(double meters) {
  if (meters <= 0 || !meters.isFinite) return 0;
  final magnitude = math.pow(10, (math.log(meters) / math.ln10).floor());
  for (final factor in [5, 2, 1]) {
    final candidate = factor * magnitude;
    if (candidate <= meters) return candidate.toDouble();
  }
  return magnitude.toDouble();
}

class _GridPainter extends CustomPainter {
  _GridPainter(
    this.camera, {
    required this.background,
    required this.showScaleBar,
    required this.lineOpacity,
  });

  final MapCamera camera;
  final bool background;
  final bool showScaleBar;
  final double lineOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (background) {
      canvas.drawRect(Offset.zero & size, Paint()..color = ink);
    }
    final center = camera.center;
    final probe = camera.latLngToScreenOffset(
      LatLng(math.min(center.latitude + 0.001, 89.9), center.longitude),
    );
    final pixelsPerDegree =
        (probe - camera.latLngToScreenOffset(center)).distance * 1000;
    if (!pixelsPerDegree.isFinite || pixelsPerDegree <= 0) return;
    final step = gridStepDegrees(pixelsPerDegree);
    final bounds = camera.visibleBounds;

    if (lineOpacity > 0) {
      _paintLines(canvas, size, step, bounds, center);
    }
    if (!showScaleBar) return;
    _paintScaleBar(canvas, size);
  }

  void _paintLines(
    Canvas canvas,
    Size size,
    double step,
    LatLngBounds bounds,
    LatLng center,
  ) {
    final minor = Paint()
      ..color = cyan.withValues(alpha: .08 * lineOpacity)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = cyan.withValues(alpha: .2 * lineOpacity)
      ..strokeWidth = 1;

    var lines = 0;
    for (
      var lat = (bounds.south / step).floor() * step;
      lat <= bounds.north && lines < 400;
      lat += step, lines++
    ) {
      if (lat < -85 || lat > 85) continue;
      final y = camera.latLngToScreenOffset(LatLng(lat, center.longitude)).dy;
      final isMajor = ((lat / step).round() % 5) == 0;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isMajor ? major : minor,
      );
    }
    lines = 0;
    for (
      var lng = (bounds.west / step).floor() * step;
      lng <= bounds.east && lines < 400;
      lng += step, lines++
    ) {
      final x = camera.latLngToScreenOffset(LatLng(center.latitude, lng)).dx;
      final isMajor = ((lng / step).round() % 5) == 0;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? major : minor,
      );
    }
  }

  void _paintScaleBar(Canvas canvas, Size size) {
    // Scale bar in the bottom-left corner.
    final left = camera.screenOffsetToLatLng(Offset(12, size.height - 18));
    final right = camera.screenOffsetToLatLng(Offset(132, size.height - 18));
    final meters = niceScaleMeters(
      haversineMeters(
        left.latitude,
        left.longitude,
        right.latitude,
        right.longitude,
      ),
    );
    if (meters <= 0) return;
    final barPixels =
        120 *
        meters /
        haversineMeters(
          left.latitude,
          left.longitude,
          right.latitude,
          right.longitude,
        );
    final y = size.height - 14;
    final label = meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} km'
        : '${meters.toStringAsFixed(0)} m';
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: toxic, fontSize: 10, letterSpacing: .4),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Dark plate keeps the scale readable over street tiles.
    canvas.drawRRect(
      RRect.fromLTRBR(
        6,
        y - 22,
        18 + math.max(barPixels, text.width),
        y + 8,
        const Radius.circular(6),
      ),
      Paint()..color = ink.withValues(alpha: .72),
    );
    final bar = Paint()
      ..color = toxic
      ..strokeWidth = 2;
    canvas.drawLine(Offset(12, y), Offset(12 + barPixels, y), bar);
    canvas.drawLine(Offset(12, y - 4), Offset(12, y + 4), bar);
    canvas.drawLine(
      Offset(12 + barPixels, y - 4),
      Offset(12 + barPixels, y + 4),
      bar,
    );
    text.paint(canvas, Offset(12, y - 18));
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.background != background ||
      oldDelegate.showScaleBar != showScaleBar ||
      oldDelegate.lineOpacity != lineOpacity;
}
