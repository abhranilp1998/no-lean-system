import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';

DangerZone zone({
  String id = 'z1',
  String name = 'Corner shop',
  double lat = 22.5726,
  double lng = 88.3639,
  double radius = 200,
}) => DangerZone(
  id: id,
  name: name,
  latitude: lat,
  longitude: lng,
  radiusMeters: radius,
  createdAt: DateTime(2026, 10, 8),
);

void main() {
  test('round-trips through JSON', () {
    final original = zone();
    final decoded = DangerZone.fromJson(original.toJson());
    expect(decoded.toJson(), original.toJson());
  });

  test('rejects out-of-range fields', () {
    for (final bad in [
      zone(name: '  '),
      zone(name: 'x' * 41),
      zone(lat: 91),
      zone(lng: -181),
      zone(radius: 99),
      zone(radius: 2001),
      zone(lat: double.nan),
    ]) {
      expect(bad.validate, throwsFormatException);
    }
  });

  test('decodeList rejects duplicates, overflow and malformed items', () {
    expect(
      () => DangerZone.decodeList([zone().toJson(), zone().toJson()]),
      throwsFormatException,
    );
    expect(
      () => DangerZone.decodeList([
        for (var i = 0; i <= DangerZone.maxZones; i++) zone(id: 'z$i').toJson(),
      ]),
      throwsFormatException,
    );
    expect(() => DangerZone.decodeList([42]), throwsFormatException);
    expect(DangerZone.decodeList(null), isEmpty);
  });

  test('haversine distance matches known values', () {
    // ~111.2 km per degree of latitude.
    expect(haversineMeters(0, 0, 1, 0), closeTo(111195, 50));
    // Kolkata → Howrah station is roughly 3.6 km.
    final d = haversineMeters(22.5726, 88.3639, 22.5839, 88.3426);
    expect(d, inInclusiveRange(2300, 2600));
    expect(zone().distanceTo(22.5726, 88.3639), closeTo(0, 0.001));
  });
}
