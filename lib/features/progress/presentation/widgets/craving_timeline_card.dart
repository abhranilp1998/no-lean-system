import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../domain/recovery_insights.dart';

class CravingTimelineCard extends StatelessWidget {
  const CravingTimelineCard({required this.points, super.key});

  final List<CravingSeriesPoint> points;

  @override
  Widget build(BuildContext context) {
    final peak = points.fold<int>(
      0,
      (value, point) => math.max(value, point.intensity),
    );
    final semantics = points.isEmpty
        ? 'No craving intensity entries logged.'
        : '${points.length} cravings in chronological order. '
              'Peak intensity $peak out of 10.';

    return GlassCard(
      accent: cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CRAVING SIGNAL', style: microStyle.copyWith(color: cyan)),
              const Spacer(),
              Text(
                'OLDEST → NEWEST',
                style: microStyle.copyWith(
                  color: muted,
                  fontSize: 8.5,
                  letterSpacing: .7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Semantics(
            label: semantics,
            image: true,
            child: SizedBox(
              height: 142,
              child: points.isEmpty
                  ? const _EmptyTimeline()
                  : CustomPaint(
                      painter: _TimelinePainter(points),
                      child: const SizedBox.expand(),
                    ),
            ),
          ),
          const SizedBox(height: 9),
          if (points.isEmpty)
            const Text(
              'Log signals to reveal intensity movement over time.',
              style: TextStyle(fontSize: 11, color: muted),
            )
          else
            Row(
              children: [
                Text(
                  _stamp(points.first.timestamp),
                  style: microStyle.copyWith(color: muted),
                ),
                const Spacer(),
                Text(
                  'PEAK $peak / 10',
                  style: microStyle.copyWith(color: cyan),
                ),
                const Spacer(),
                Text(
                  _stamp(points.last.timestamp),
                  style: microStyle.copyWith(color: muted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TimelineGridPainter(),
    child: const Center(
      child: Icon(Icons.show_chart_rounded, color: muted, size: 28),
    ),
  );
}

class _TimelineGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => _paintGrid(canvas, size);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.points);

  final List<CravingSeriesPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    if (points.isEmpty) return;

    final line = Paint()
      ..color = cyan
      ..strokeWidth = 2.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final glow = Paint()
      ..color = cyan.withValues(alpha: .22)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [cyan.withValues(alpha: .25), Colors.transparent],
      ).createShader(Offset.zero & size);
    final path = Path();
    final area = Path();
    final offsets = _pointOffsets(size);

    for (var index = 0; index < offsets.length; index++) {
      final point = offsets[index];
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
        area
          ..moveTo(point.dx, size.height)
          ..lineTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
        area.lineTo(point.dx, point.dy);
      }
    }
    area
      ..lineTo(offsets.last.dx, size.height)
      ..close();

    canvas
      ..drawPath(area, fill)
      ..drawPath(path, glow)
      ..drawPath(path, line);

    final markerStep = math.max(1, (points.length / 18).ceil());
    for (var index = 0; index < offsets.length; index += markerStep) {
      _drawMarker(canvas, offsets[index]);
    }
    if ((offsets.length - 1) % markerStep != 0) {
      _drawMarker(canvas, offsets.last);
    }
  }

  List<Offset> _pointOffsets(Size size) {
    final firstTime = points.first.timestamp.millisecondsSinceEpoch;
    final lastTime = points.last.timestamp.millisecondsSinceEpoch;
    final timeSpan = lastTime - firstTime;

    return List.generate(points.length, (index) {
      final point = points[index];
      final xRatio = timeSpan == 0
          ? (points.length == 1 ? .5 : index / (points.length - 1))
          : (point.timestamp.millisecondsSinceEpoch - firstTime) / timeSpan;
      final yRatio = point.intensity.clamp(0, 10) / 10;
      return Offset(xRatio * size.width, size.height - yRatio * size.height);
    });
  }

  void _drawMarker(Canvas canvas, Offset point) {
    canvas
      ..drawCircle(point, 4, Paint()..color = panel)
      ..drawCircle(point, 2.5, Paint()..color = cyan);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    if (identical(points, oldDelegate.points)) return false;
    if (points.length != oldDelegate.points.length) return true;
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final old = oldDelegate.points[index];
      if (current.timestamp != old.timestamp ||
          current.intensity != old.intensity) {
        return true;
      }
    }
    return false;
  }
}

void _paintGrid(Canvas canvas, Size size) {
  final grid = Paint()
    ..color = muted.withValues(alpha: .14)
    ..strokeWidth = 1;
  for (final ratio in const [0.0, .5, 1.0]) {
    final y = size.height * ratio;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
  }
  for (final ratio in const [0.0, .25, .5, .75, 1.0]) {
    final x = size.width * ratio;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
  }
}

String _stamp(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
