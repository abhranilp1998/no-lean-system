import 'dart:math';
import 'dart:ui';

import '../../zones/domain/danger_zone.dart';

const radarArtSize = Size(720, 960);

/// Projects zones onto the art with a local equirectangular projection,
/// centred on the zones and fitted with a margin. Good to well under a
/// percent at city scale, which is all a home-screen snapshot needs.
class RadarProjection {
  RadarProjection(List<DangerZone> zones, this.size)
    : assert(zones.isNotEmpty) {
    const metresPerDegree = 111320.0;
    _lat0 = zones.map((z) => z.latitude).reduce((a, b) => a + b) / zones.length;
    _lng0 =
        zones.map((z) => z.longitude).reduce((a, b) => a + b) / zones.length;
    _mx = metresPerDegree * cos(_lat0 * pi / 180);
    _my = metresPerDegree;
    var extent = 0.0;
    for (final z in zones) {
      final dx = (z.longitude - _lng0).abs() * _mx + z.radiusMeters;
      final dy = (z.latitude - _lat0).abs() * _my + z.radiusMeters;
      extent = max(extent, max(dx, dy));
    }
    // Half the shorter side, minus a margin, covers the furthest zone edge.
    pixelsPerMetre =
        (min(size.width, size.height) / 2 * 0.8) / max(extent, 300);
  }

  final Size size;
  late final double _lat0, _lng0, _mx, _my;
  late final double pixelsPerMetre;

  Offset project(double lat, double lng) => Offset(
    size.width / 2 + (lng - _lng0) * _mx * pixelsPerMetre,
    size.height / 2 - (lat - _lat0) * _my * pixelsPerMetre,
  );
}

/// Dark grid (same look as the in-app offline map) with zone circles. No
/// names or labels are drawn, so the snapshot says nothing on a home screen.
void paintRadar(Canvas canvas, Size size, List<DangerZone> zones) {
  final rect = Offset.zero & size;
  canvas.drawRect(rect, Paint()..color = const Color(0xFF070B16));
  final grid = Paint()
    ..color = const Color(0x334DE8FF)
    ..strokeWidth = 1;
  for (var x = 0.0; x <= size.width; x += 60) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
  }
  for (var y = 0.0; y <= size.height; y += 60) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
  }
  final centre = rect.center;
  final ring = Paint()
    ..color = const Color(0x554DE8FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  for (var r = 1; r <= 3; r++) {
    canvas.drawCircle(centre, min(size.width, size.height) * 0.15 * r, ring);
  }
  if (zones.isEmpty) return;
  final projection = RadarProjection(zones, size);
  for (final zone in zones) {
    final c = projection.project(zone.latitude, zone.longitude);
    final r = zone.radiusMeters * projection.pixelsPerMetre;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = Gradient.radial(c, r, const [
          Color(0x99FF5364),
          Color(0x22FF5364),
        ]),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFFFF5364)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
}
