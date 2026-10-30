import 'dart:math';
import 'dart:ui';

import '../domain/garden.dart';

/// Widget art size. Portrait; the widget centre-crops it to any shape.
const gardenArtSize = Size(720, 960);

/// Paints the garden. [evening] gives the static night variant: dark sky,
/// moon and still fireflies (widgets cannot animate). No text, so nothing on
/// the home screen says what is being counted.
void paintGarden(
  Canvas canvas,
  Size size,
  Garden garden, {
  bool evening = false,
}) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        evening
            ? const [Color(0xFF070B16), Color(0xFF1A1236), Color(0xFF0B1A14)]
            : const [Color(0xFF9FD8FF), Color(0xFFDFF3FF), Color(0xFFBFE8B0)],
        const [0, 0.55, 1],
      ),
  );
  final groundTop = size.height * 0.52;
  canvas.drawRect(
    Rect.fromLTRB(0, groundTop, size.width, size.height),
    Paint()
      ..color = evening ? const Color(0xFF0E2418) : const Color(0xFF6DBE5A),
  );
  if (evening) {
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.12),
      34,
      Paint()..color = const Color(0xFFFFF4C8),
    );
  } else {
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.1),
      44,
      Paint()..color = const Color(0xFFFFE27A),
    );
  }

  // Trees along the horizon, one per milestone.
  for (var i = 0; i < garden.trees; i++) {
    final x = size.width * (0.12 + 0.19 * i);
    final h = 150.0 + 25 * i;
    canvas.drawRect(
      Rect.fromLTWH(x - 9, groundTop - h * 0.45, 18, h * 0.45 + 12),
      Paint()
        ..color = evening ? const Color(0xFF3A2A1E) : const Color(0xFF8A5A36),
    );
    canvas.drawCircle(
      Offset(x, groundTop - h * 0.6),
      h * 0.32,
      Paint()
        ..color = evening ? const Color(0xFF1C4A2E) : const Color(0xFF2E8B4A),
    );
  }

  // Plants: 7 per row, newest at the front.
  const perRow = 7;
  final rows = max(1, (garden.plants.length / perRow).ceil());
  final rowGap = (size.height - groundTop - 40) / max(rows, 6);
  final cell = size.width / perRow;
  for (var i = 0; i < garden.plants.length; i++) {
    final plant = garden.plants[i];
    final row = i ~/ perRow;
    final col = i % perRow;
    final rnd = Random(plant.day.millisecondsSinceEpoch ~/ 86400000);
    final scale = 0.6 + 0.6 * (row + 1) / rows;
    final base = Offset(
      cell * (col + 0.5) + rnd.nextDouble() * 14 - 7,
      groundTop + 30 + rowGap * row,
    );
    _plant(canvas, base, scale, plant.state, evening, rnd);
  }

  if (evening) {
    final rnd = Random(garden.plants.length);
    final glow = Paint()
      ..color = const Color(0xCCFFF59D)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (var i = 0; i < 14; i++) {
      canvas.drawCircle(
        Offset(
          rnd.nextDouble() * size.width,
          size.height * (0.3 + rnd.nextDouble() * 0.6),
        ),
        5,
        glow,
      );
    }
  }
}

void _plant(
  Canvas canvas,
  Offset base,
  double scale,
  PlantState state,
  bool evening,
  Random rnd,
) {
  final wilted = state == PlantState.wilted;
  final stemColor = wilted
      ? const Color(0xFF8C7A4A)
      : (evening ? const Color(0xFF3FA36A) : const Color(0xFF2F7D32));
  final h = 46 * scale;
  final lean = wilted ? 16 * scale : rnd.nextDouble() * 6 - 3;
  final top = base + Offset(lean, -h);
  final stem = Path()
    ..moveTo(base.dx, base.dy)
    ..quadraticBezierTo(base.dx, base.dy - h * 0.6, top.dx, top.dy);
  canvas.drawPath(
    stem,
    Paint()
      ..color = stemColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * scale
      ..strokeCap = StrokeCap.round,
  );
  final leaf = Paint()..color = stemColor;
  canvas.drawOval(
    Rect.fromCenter(
      center: base + Offset(-8 * scale, -h * 0.45),
      width: 16 * scale,
      height: 8 * scale,
    ),
    leaf,
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: base + Offset(8 * scale, -h * 0.6),
      width: 16 * scale,
      height: 8 * scale,
    ),
    leaf,
  );
  final bloom = wilted
      ? const Color(0xFF9E8E6A)
      : const [
          Color(0xFFFF8FB1),
          Color(0xFFFFD25E),
          Color(0xFFB39DFF),
          Color(0xFF7FE0FF),
        ][rnd.nextInt(4)];
  canvas.drawCircle(top, (wilted ? 6 : 9) * scale, Paint()..color = bloom);
}
