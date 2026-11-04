import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:no_lean/features/zones/domain/background_zone_alert.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';
import 'package:no_lean/features/zones/services/native_geofence_gateway.dart';

void main() {
  final zone = DangerZone(
    id: 'z1',
    name: 'Panacea',
    latitude: 22.5,
    longitude: 88.3,
    radiusMeters: 200,
    createdAt: DateTime(2026, 10, 1),
  );
  String state({bool background = true}) => jsonEncode({
    'backgroundGeofencing': background,
    'zones': [zone.toJson()],
  });

  test('zone geofence uses ENTER + DWELL with an initial ENTER', () {
    final fence = NativeGeofenceGateway.geofenceFor(zone);
    expect(fence.triggers, {GeofenceEvent.enter, GeofenceEvent.dwell});
    expect(fence.androidSettings.initialTriggers, {GeofenceEvent.enter});
  });

  test('early-warning ring is wider and enter-only', () {
    final ring = NativeGeofenceGateway.nearGeofenceFor(zone);
    expect(ring.id, 'nolean_near_z1');
    expect(ring.radiusMeters, 600);
    expect(ring.triggers, {GeofenceEvent.enter});
  });

  test('near alert names the zone; off when background alerts are off', () {
    final copy = backgroundNearAlert(
      rawState: state(),
      geofenceIds: ['nolean_near_z1'],
    );
    expect(copy!.title, contains('Panacea'));
    expect(copy.body, contains('getting close'));
    expect(
      backgroundNearAlert(
        rawState: state(background: false),
        geofenceIds: ['nolean_near_z1'],
      ),
      isNull,
    );
    expect(
      backgroundNearAlert(rawState: state(), geofenceIds: ['nolean_zone_z1']),
      isNull,
    );
  });
}
