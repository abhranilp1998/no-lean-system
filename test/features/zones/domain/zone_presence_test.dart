import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/domain/zone_presence.dart';

void main() {
  final zone = DangerZone(
    id: 'z1',
    name: 'Corner shop',
    latitude: 22.5726,
    longitude: 88.3639,
    radiusMeters: 200,
    createdAt: DateTime(2026, 10, 8),
  );
  // ~0.0009° latitude ≈ 100 m.
  LocationFix at(double metersNorth, DateTime t, {double accuracy = 20}) =>
      LocationFix(
        latitude: zone.latitude + metersNorth / 111195,
        longitude: zone.longitude,
        accuracyMeters: accuracy,
        at: t,
      );
  final t0 = DateTime(2026, 10, 8, 18);

  test('alerts once on entry, not while staying inside', () {
    final tracker = ZonePresenceTracker();
    expect(tracker.update([zone], at(500, t0)), isEmpty);
    expect(tracker.update([zone], at(150, t0)), [zone]);
    expect(tracker.update([zone], at(50, t0)), isEmpty);
    expect(tracker.insideZoneIds, {'z1'});
  });

  test('edge jitter does not flap; a clear exit re-arms', () {
    final tracker = ZonePresenceTracker(realertAfter: Duration.zero);
    expect(tracker.update([zone], at(190, t0)), [zone]);
    expect(tracker.update([zone], at(215, t0)), isEmpty); // within margin
    expect(tracker.update([zone], at(195, t0)), isEmpty);
    expect(tracker.update([zone], at(300, t0)), isEmpty); // exited
    expect(tracker.insideZoneIds, isEmpty);
    expect(tracker.update([zone], at(100, t0)), [zone]);
  });

  test('re-entry within the cooldown does not alert again', () {
    final tracker = ZonePresenceTracker();
    expect(tracker.update([zone], at(0, t0)), [zone]);
    tracker.update([zone], at(600, t0.add(const Duration(minutes: 5))));
    expect(
      tracker.update([zone], at(0, t0.add(const Duration(minutes: 10)))),
      isEmpty,
    );
    tracker.update([zone], at(600, t0.add(const Duration(minutes: 20))));
    expect(tracker.update([zone], at(0, t0.add(const Duration(minutes: 31)))), [
      zone,
    ]);
  });

  test('coarse fixes are ignored instead of raising false alarms', () {
    final tracker = ZonePresenceTracker();
    expect(tracker.update([zone], at(0, t0, accuracy: 500)), isEmpty);
    expect(tracker.update([zone], at(0, t0, accuracy: 250)), isEmpty);
    expect(tracker.insideZoneIds, isEmpty);
  });

  test('deleted zones are forgotten', () {
    final tracker = ZonePresenceTracker();
    tracker.update([zone], at(0, t0));
    tracker.update(const [], at(0, t0));
    expect(tracker.insideZoneIds, isEmpty);
  });
}
