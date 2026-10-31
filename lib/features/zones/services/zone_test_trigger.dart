import 'dart:async';

import '../domain/danger_zone.dart';

/// Test-only hook: lets the Danger Zones screen fire the same entry path
/// (alert + lock) that a real zone entry would, without walking anywhere.
class ZoneTestTrigger {
  ZoneTestTrigger._();
  static final instance = ZoneTestTrigger._();
  final _controller = StreamController<DangerZone>.broadcast();
  Stream<DangerZone> get stream => _controller.stream;
  void fire(DangerZone zone) => _controller.add(zone);
}

const testZoneName = 'TEST ZONE (here)';
const testZoneRadiusMeters = 150.0;
