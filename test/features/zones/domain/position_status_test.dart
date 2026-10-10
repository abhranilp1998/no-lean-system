import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/domain/position_status.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';

void main() {
  final bar = DangerZone(
    id: 'bar',
    name: 'Bar',
    latitude: 22.5726,
    longitude: 88.3639,
    radiusMeters: 200,
    createdAt: DateTime(2026, 10, 1),
  );
  // ~1.1 km north of the bar.
  final shop = DangerZone(
    id: 'shop',
    name: 'Shop',
    latitude: 22.5826,
    longitude: 88.3639,
    radiusMeters: 100,
    createdAt: DateTime(2026, 10, 1),
  );

  LocationFix at(double lat, double lng, {double accuracy = 12}) => LocationFix(
    latitude: lat,
    longitude: lng,
    accuracyMeters: accuracy,
    at: DateTime(2026, 10, 10, 12),
  );

  group('buildPositionStatusText', () {
    test('inside a zone names it and shows rounded coordinates', () {
      final text = buildPositionStatusText(
        availability: PositionAvailability.fix,
        zones: [bar, shop],
        hideSensitive: false,
        fix: at(22.57261234, 88.36398765),
      );
      expect(text.title, 'INSIDE Bar');
      expect(text.body, '22.573, 88.364 // ±12 m');
      expect(text.stateKey, 'inside:bar');
    });

    test('outside shows the nearest zone and distance to its edge', () {
      // ~556 m south of the bar centre -> ~356 m to its edge.
      final text = buildPositionStatusText(
        availability: PositionAvailability.fix,
        zones: [bar, shop],
        hideSensitive: false,
        fix: at(22.5676, 88.3639),
      );
      expect(text.title, 'Position 22.568, 88.364');
      expect(text.body, startsWith('Nearest: Bar // '));
      expect(text.body, endsWith(' to edge // ±12 m'));
      final metres = int.parse(
        RegExp(r'// (\d+) m to edge').firstMatch(text.body)!.group(1)!,
      );
      expect(metres, inInclusiveRange(345, 365));
      expect(text.stateKey, 'outside');
    });

    test('kilometre distances and no zones', () {
      expect(formatPositionDistance(340.4), '340 m');
      expect(formatPositionDistance(1234), '1.2 km');
      expect(formatPositionDistance(12345), '12 km');
      final none = buildPositionStatusText(
        availability: PositionAvailability.fix,
        zones: const [],
        hideSensitive: false,
        fix: at(22.5, 88.3, accuracy: double.nan),
      );
      expect(none.title, 'Position 22.500, 88.300');
      expect(none.body, 'No danger zones marked');
    });

    test('overlapping zones pick the closest centre', () {
      final wide = DangerZone(
        id: 'wide',
        name: 'Wide',
        latitude: 22.5736,
        longitude: 88.3639,
        radiusMeters: 2000,
        createdAt: DateTime(2026, 10, 1),
      );
      final text = buildPositionStatusText(
        availability: PositionAvailability.fix,
        zones: [wide, bar],
        hideSensitive: false,
        fix: at(bar.latitude, bar.longitude),
      );
      expect(text.title, 'INSIDE Bar');
    });

    test('location off, no permission and locating', () {
      String title(PositionAvailability a) => buildPositionStatusText(
        availability: a,
        zones: [bar],
        hideSensitive: false,
      ).title;
      expect(title(PositionAvailability.locationOff), 'Position: location off');
      expect(
        title(PositionAvailability.noPermission),
        'Position: no permission',
      );
      expect(title(PositionAvailability.locating), 'Position: locating…');
      // "fix" without a fix degrades to locating instead of crashing.
      expect(title(PositionAvailability.fix), 'Position: locating…');
    });

    test('hide sensitive never shows zone names or coordinates', () {
      for (final availability in PositionAvailability.values) {
        final text = buildPositionStatusText(
          availability: availability,
          zones: [bar],
          hideSensitive: true,
          fix: at(bar.latitude, bar.longitude),
        );
        expect(text.title, neutralPositionTitle);
        expect(text.body, neutralPositionBody);
        expect('${text.title} ${text.body}', isNot(contains('Bar')));
        expect('${text.title} ${text.body}', isNot(contains('22.')));
        expect('${text.title} ${text.body}', isNot(contains('INSIDE')));
      }
    });
  });

  group('PositionStatusThrottle', () {
    const outsideA = PositionStatusText(
      title: 'Position 1.000, 1.000',
      body: 'a',
      stateKey: 'outside',
    );
    const outsideB = PositionStatusText(
      title: 'Position 1.001, 1.000',
      body: 'b',
      stateKey: 'outside',
    );
    const inside = PositionStatusText(
      title: 'INSIDE Bar',
      body: 'c',
      stateKey: 'inside:bar',
    );
    final t0 = DateTime(2026, 10, 10, 12);

    test('first post goes out, drift waits 15 s', () {
      final throttle = PositionStatusThrottle();
      expect(throttle.shouldPost(outsideA, t0), isTrue);
      expect(
        throttle.shouldPost(outsideB, t0.add(const Duration(seconds: 5))),
        isFalse,
      );
      expect(
        throttle.shouldPost(outsideB, t0.add(const Duration(seconds: 14))),
        isFalse,
      );
      expect(
        throttle.shouldPost(outsideB, t0.add(const Duration(seconds: 15))),
        isTrue,
      );
    });

    test('a state change posts immediately', () {
      final throttle = PositionStatusThrottle();
      expect(throttle.shouldPost(outsideA, t0), isTrue);
      expect(
        throttle.shouldPost(inside, t0.add(const Duration(seconds: 1))),
        isTrue,
      );
      // ...and back out again is also a state change.
      expect(
        throttle.shouldPost(outsideA, t0.add(const Duration(seconds: 2))),
        isTrue,
      );
    });

    test('unchanged text re-posts after the interval (heartbeat)', () {
      final throttle = PositionStatusThrottle();
      expect(throttle.shouldPost(outsideA, t0), isTrue);
      expect(
        throttle.shouldPost(outsideA, t0.add(const Duration(seconds: 15))),
        isTrue,
      );
    });

    test('reset and a backwards clock never stall it', () {
      final throttle = PositionStatusThrottle();
      expect(throttle.shouldPost(outsideA, t0), isTrue);
      throttle.reset();
      expect(throttle.shouldPost(outsideA, t0), isTrue);
      expect(
        throttle.shouldPost(outsideB, t0.subtract(const Duration(minutes: 1))),
        isTrue,
      );
    });
  });
}
