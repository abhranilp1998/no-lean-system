import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../core/theme/app_theme.dart';

/// Builds a 4x5 colour matrix that turns light OSM tiles into the app's dark
/// neon style: invert luminance (light land → near-black, dark labels →
/// bright), boost contrast, tint toward [tint], and lift blacks to [base].
List<double> neonTileMatrix({
  Color tint = cyan,
  Color base = ink,
  double gain = 1.35,
}) {
  const lr = .2126, lg = .7152, lb = .0722;
  List<double> row(double t, double b) {
    final k = gain * t;
    return [-k * lr, -k * lg, -k * lb, 0, k * 255 + b * 255];
  }

  return [
    ...row(tint.r * .55, base.r),
    ...row(tint.g * .8, base.g),
    ...row(tint.b * .9, base.b),
    0, 0, 0, 1, 0, //
  ];
}

final noLeanTileMatrix = neonTileMatrix();

/// Applies a colour matrix to one colour (for tests and previews).
Color applyColorMatrix(List<double> m, Color c) {
  double ch(int row) {
    final o = row * 5;
    final v =
        m[o] * c.r * 255 +
        m[o + 1] * c.g * 255 +
        m[o + 2] * c.b * 255 +
        m[o + 3] * c.a * 255 +
        m[o + 4];
    return v.clamp(0, 255) / 255;
  }

  return Color.from(alpha: ch(3), red: ch(0), green: ch(1), blue: ch(2));
}

/// Tile builder that restyles each OSM tile.
Widget neonTileBuilder(BuildContext context, Widget tile, TileImage image) =>
    ColorFiltered(
      colorFilter: ColorFilter.matrix(noLeanTileMatrix),
      child: tile,
    );

/// Visible OSM attribution styled for the app. Required by the OSM tile usage
/// policy whenever street tiles are shown.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: ink.withValues(alpha: .78),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: cyan.withValues(alpha: .25)),
          ),
          child: InkWell(
            key: const ValueKey('osm-attribution'),
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(color: Colors.white70, fontSize: 9.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// HUD corner brackets drawn over the map frame.
class MapHudFrame extends StatelessWidget {
  const MapHudFrame({this.color = cyan, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(size: Size.infinite, painter: _HudPainter(color)),
  );
}

class _HudPainter extends CustomPainter {
  _HudPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 18.0, inset = 8.0;
    final paint = Paint()
      ..color = color.withValues(alpha: .75)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final corners = [
      (const Offset(inset, inset), 1.0, 1.0),
      (Offset(size.width - inset, inset), -1.0, 1.0),
      (Offset(inset, size.height - inset), 1.0, -1.0),
      (Offset(size.width - inset, size.height - inset), -1.0, -1.0),
    ];
    for (final (point, dx, dy) in corners) {
      canvas
        ..drawLine(point, point.translate(arm * dx, 0), paint)
        ..drawLine(point, point.translate(0, arm * dy), paint);
    }
    // Faint scanlines keep the street layer in the app's visual language.
    final scan = Paint()..color = Colors.black.withValues(alpha: .12);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), scan);
    }
    // Vignette.
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, ink.withValues(alpha: .55)],
          stops: const [.62, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HudPainter oldDelegate) => oldDelegate.color != color;
}
