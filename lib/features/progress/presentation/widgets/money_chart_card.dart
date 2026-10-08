import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/no_lean_visuals.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../domain/money_series.dart';

/// Cumulative saved vs. lost, or a prompt to set the daily spend when it is
/// still ₹0 (nothing to chart without it).
class MoneyChartCard extends StatelessWidget {
  const MoneyChartCard({
    required this.points,
    required this.dailySpend,
    required this.onSetSpend,
    super.key,
  });

  final List<MoneyPoint> points;
  final double dailySpend;
  final VoidCallback onSetSpend;

  @override
  Widget build(BuildContext context) {
    if (dailySpend <= 0) {
      return GlassCard(
        key: const ValueKey('money-chart-prompt'),
        accent: toxic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MONEY // NOT SET', style: microStyle.copyWith(color: toxic)),
            const SizedBox(height: 10),
            const Text(
              'Daily spend is ₹0, so there is nothing to measure. Set what a '
              'usual day cost you and this chart shows money kept against '
              'money lost, from day one.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('money-set-spend'),
              onPressed: onSetSpend,
              style: FilledButton.styleFrom(backgroundColor: toxic),
              child: const Text(
                'SET DAILY SPEND',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      );
    }
    final last = points.isEmpty ? null : points.last;
    final saved = last?.saved ?? 0;
    final lost = last?.lost ?? 0;
    return GlassCard(
      key: const ValueKey('money-chart'),
      accent: toxic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MONEY // KEPT VS LOST',
            style: microStyle.copyWith(color: toxic),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Total('KEPT', saved, toxic)),
              Expanded(child: _Total('LOST', lost, red)),
              Expanded(child: _Total('NET', saved - lost, cyan)),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            label:
                'Money chart. ${money(saved)} kept and ${money(lost)} lost '
                'since ${points.isEmpty ? 'today' : DateFormat('d MMM').format(points.first.day)}.',
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                painter: MoneyChartPainter(
                  points: points,
                  glow: NoLeanVisuals.of(context).glowOpacity(.35),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (points.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('d MMM yy').format(points.first.day),
                  style: microStyle.copyWith(color: muted),
                ),
                Text('TODAY', style: microStyle.copyWith(color: muted)),
              ],
            ),
          const SizedBox(height: 6),
          Text(
            'ESTIMATE // ${money(dailySpend)} PER DAY, EVERY RELAPSE DAY '
            'COUNTED AS LOST',
            style: microStyle.copyWith(color: muted, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value, this.color);

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: microStyle.copyWith(color: muted)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          money(value),
          style: displayFont(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    ],
  );
}

/// Two cumulative lines on one scale: kept (toxic, filled) and lost (red).
class MoneyChartPainter extends CustomPainter {
  const MoneyChartPainter({required this.points, required this.glow});

  final List<MoneyPoint> points;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.isEmpty) return;
    final top = points
        .map((p) => math.max(p.saved, p.lost))
        .fold<double>(1, math.max);
    Offset at(int i, double value) => Offset(
      points.length == 1 ? size.width : size.width * i / (points.length - 1),
      size.height - size.height * (value / top),
    );
    Path line(double Function(MoneyPoint) pick) {
      final path = Path()
        ..moveTo(at(0, pick(points[0])).dx, at(0, pick(points[0])).dy);
      if (points.length == 1) {
        path
          ..reset()
          ..moveTo(0, at(0, pick(points[0])).dy)
          ..lineTo(size.width, at(0, pick(points[0])).dy);
        return path;
      }
      for (var i = 1; i < points.length; i++) {
        final p = at(i, pick(points[i]));
        path.lineTo(p.dx, p.dy);
      }
      return path;
    }

    final saved = line((p) => p.saved);
    final fill = Path.from(saved)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [toxic.withValues(alpha: .28), toxic.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;
    if (glow > 0) {
      canvas.drawPath(
        saved,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = toxic.withValues(alpha: glow * .5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawPath(saved, stroke..color = toxic);
    canvas.drawPath(line((p) => p.lost), stroke..color = red);
  }

  @override
  bool shouldRepaint(MoneyChartPainter old) =>
      old.points != points || old.glow != glow;
}
