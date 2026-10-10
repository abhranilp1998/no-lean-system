import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/zones/domain/background_zone_alert.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';

void main() {
  final zone = DangerZone(
    id: 'z1',
    name: 'Bar',
    latitude: 22.57,
    longitude: 88.36,
    radiusMeters: 200,
    createdAt: DateTime(2026, 10, 1),
  );
  final now = DateTime(2026, 10, 8, 18);
  String state({bool enabled = true, List<Object?>? events}) => jsonEncode({
    'stateVersion': 9,
    'backgroundGeofencing': enabled,
    'zones': [zone.toJson()],
    'riskWindow': {'startMinutes': 17 * 60, 'endMinutes': 21 * 60},
    'events': events ?? [],
  });

  test('builds zone copy from the local state file', () {
    final relapse = RecoveryEvent.create(
      type: RecoveryEventType.relapse,
      timestamp: DateTime(2026, 10, 4, 22),
    );
    final copy = backgroundZoneAlert(
      rawState: state(events: [relapse.toJson()]),
      geofenceIds: [geofenceIdForZone(zone)],
      now: now,
    )!;
    expect(copy.title, 'DANGER ZONE // BAR');
    expect(copy.body, contains('Clean since 4 Oct.'));
    expect(copy.body, contains('risk window'));
  });

  test('stale geofences stay silent once background alerts are off', () {
    expect(
      backgroundZoneAlert(
        rawState: state(enabled: false),
        geofenceIds: [geofenceIdForZone(zone)],
        now: now,
      ),
      isNull,
    );
    expect(
      backgroundZoneAlert(
        rawState: state(),
        geofenceIds: ['nolean_zone_deleted', 'other_app_fence'],
        now: now,
      ),
      isNull,
    );
  });

  test('an unreadable state file still alerts with generic copy', () {
    final copy = backgroundZoneAlert(
      rawState: '{broken',
      geofenceIds: [geofenceIdForZone(zone)],
      now: now,
    )!;
    expect(copy.title, 'DANGER ZONE');
    expect(copy.body, contains('open SOS'));
  });
}
