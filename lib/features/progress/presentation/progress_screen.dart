import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/brand_header.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/craving_entry.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final maxIntensity = recovery.cravings.isEmpty
        ? 0
        : recovery.cravings.map((entry) => entry.intensity).reduce(math.max);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Text('PROGRESS', style: eyebrowStyle.copyWith(color: purple)),
        const SizedBox(height: 7),
        Text(
          'Evidence beats vibes.',
          style: displayFont(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        GlassCard(
          accent: purple,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CLEAN DAYS / LAST 30',
                style: microStyle.copyWith(color: purple),
              ),
              const SizedBox(height: 18),
              _CleanHeatMap(cleanDays: recovery.cleanDays),
              const SizedBox(height: 14),
              Row(
                children: [
                  const StatusPill(label: 'ACTIVE', color: toxic),
                  const SizedBox(width: 8),
                  Text(
                    '${recovery.streak} day current streak',
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GlassCard(
          accent: cyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CRAVING INTENSITY',
                style: microStyle.copyWith(color: cyan),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 140,
                child: _IntensityChart(entries: recovery.cravings),
              ),
              const SizedBox(height: 8),
              Text(
                recovery.cravings.isEmpty
                    ? 'Log signals to reveal your triggers.'
                    : 'Peak logged intensity: $maxIntensity / 10',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('MILESTONE TRACKER', style: eyebrowStyle.copyWith(color: muted)),
        const SizedBox(height: 10),
        const _MilestoneRow(days: 3, label: 'BREAK THE LOOP', color: cyan),
        const _MilestoneRow(days: 7, label: 'FIRST WEEK', color: purple),
        const _MilestoneRow(
          days: 14,
          label: 'HABIT PRESSURE DROPS',
          color: magenta,
        ),
        const _MilestoneRow(days: 30, label: 'NEW BASELINE', color: toxic),
        const _MilestoneRow(days: 60, label: 'SYSTEM REBUILT', color: cyan),
        const _MilestoneRow(days: 90, label: 'LONG GAME', color: purple),
      ],
    );
  }
}

class _CleanHeatMap extends StatelessWidget {
  const _CleanHeatMap({required this.cleanDays});

  final Map<String, bool> cleanDays;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: List.generate(30, (index) {
        final day = today.subtract(Duration(days: 29 - index));
        final status = cleanDays[dateKey(day)];
        final color = status == true
            ? cyan.withValues(alpha: .85)
            : status == false
            ? red.withValues(alpha: .65)
            : panelRaised;
        return Container(
          width: 19,
          height: 19,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _IntensityChart extends StatelessWidget {
  const _IntensityChart({required this.entries});

  final List<CravingEntry> entries;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ChartPainter(
      entries.map((entry) => entry.intensity.toDouble()).toList(),
    ),
    child: const SizedBox.expand(),
  );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.points);

  final List<double> points;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = muted.withValues(alpha: .18)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axis,
    );
    canvas.drawLine(const Offset(0, 0), Offset(0, size.height), axis);
    if (points.isEmpty) return;

    final line = Paint()
      ..color = cyan
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [cyan.withValues(alpha: .22), Colors.transparent],
      ).createShader(Offset.zero & size);
    final path = Path();
    final area = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1 ? 0.0 : i * size.width / (points.length - 1);
      final y = size.height - (points[i] / 10) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        area.moveTo(x, size.height);
        area.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
    }
    area.lineTo(size.width, size.height);
    area.close();
    canvas.drawPath(area, fill);
    canvas.drawPath(path, line);
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1 ? 0.0 : i * size.width / (points.length - 1);
      final y = size.height - (points[i] / 10) * size.height;
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = panel);
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = cyan);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _MilestoneRow extends ConsumerWidget {
  const _MilestoneRow({
    required this.days,
    required this.label,
    required this.color,
  });

  final int days;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(recoveryProvider).streak;
    final done = current >= days;
    final progress = (current / days).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        accent: done ? color : muted,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? color : muted,
              size: 19,
            ),
            const SizedBox(width: 11),
            SizedBox(
              width: 42,
              child: Text(
                '${days}D',
                style: displayFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: done ? color : Colors.white,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: panelRaised,
                    color: color,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              done ? 'CLEARED' : '${(progress * 100).round()}%',
              style: microStyle.copyWith(color: done ? color : muted),
            ),
          ],
        ),
      ),
    );
  }
}
