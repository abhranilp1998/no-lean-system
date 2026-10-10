import 'dart:convert';

import '../../recovery/domain/event_derived_state.dart';
import '../../recovery/domain/recovery_event.dart';
import '../../recovery/domain/risk_window.dart';
import 'danger_zone.dart';
import 'zone_alert_copy.dart';
import 'zone_entry.dart';

/// Prefix for OS geofence ids owned by NO LEAN.
const zoneGeofencePrefix = 'nolean_zone_';

String geofenceIdForZone(DangerZone zone) => '$zoneGeofencePrefix${zone.id}';

/// Builds the background alert from the persisted state file. Returns null
/// when background alerts were switched off (stale OS geofence) or none of the
/// triggered ids belong to a zone that still exists. A malformed state file
/// still alerts with generic copy: the OS only fires for zones we registered.
ZoneAlertCopy? backgroundZoneAlert({
  required String? rawState,
  required Iterable<String> geofenceIds,
  required DateTime now,
}) {
  final ids = geofenceIds
      .where((id) => id.startsWith(zoneGeofencePrefix))
      .map((id) => id.substring(zoneGeofencePrefix.length))
      .toSet();
  if (ids.isEmpty) return null;
  Map<String, dynamic> map;
  try {
    final decoded = rawState == null ? null : jsonDecode(rawState);
    if (decoded is! Map) return _generic;
    map = decoded.cast<String, dynamic>();
  } catch (_) {
    return _generic;
  }
  if (map['backgroundGeofencing'] != true) return null;
  final List<DangerZone> zones;
  try {
    zones = DangerZone.decodeList(map['zones']);
  } catch (_) {
    return _generic;
  }
  final matches = zones.where((zone) => ids.contains(zone.id)).toList();
  if (matches.isEmpty) return null;

  RiskWindow? riskWindow;
  try {
    if (map['riskWindow'] is Map) {
      riskWindow = RiskWindow.fromJson(map['riskWindow']);
    }
  } catch (_) {
    riskWindow = null;
  }
  DateTime? cleanSince;
  final rawEvents = map['events'];
  if (rawEvents is List) {
    final events = <RecoveryEvent>[];
    for (final item in rawEvents) {
      try {
        if (item is Map) {
          events.add(RecoveryEvent.fromJson(item.cast<String, dynamic>()));
        }
      } catch (_) {
        /* Skip unreadable history items; the alert still matters. */
      }
    }
    if (events.isNotEmpty) {
      final last = computeLastDose(events);
      if (!last.isAfter(now)) cleanSince = last;
    }
  }
  return buildZoneAlertCopy(
    zone: matches.first,
    now: now,
    cleanSince: cleanSince,
    riskWindow: riskWindow,
  );
}

/// Zone entries to hand to the app, only when the user opted into zone
/// history and background alerts. Name and time only.
List<ZoneEntry> backgroundZoneEntries({
  required String? rawState,
  required Iterable<String> geofenceIds,
  required DateTime now,
}) {
  final ids = geofenceIds
      .where((id) => id.startsWith(zoneGeofencePrefix))
      .map((id) => id.substring(zoneGeofencePrefix.length))
      .toSet();
  if (ids.isEmpty || rawState == null) return const [];
  try {
    final map = jsonDecode(rawState);
    if (map is! Map ||
        map['zoneHistory'] != true ||
        map['backgroundGeofencing'] != true) {
      return const [];
    }
    return [
      for (final zone in DangerZone.decodeList(map['zones']))
        if (ids.contains(zone.id)) ZoneEntry.of(zone, now, 'background'),
    ];
  } catch (_) {
    return const [];
  }
}

const _generic = ZoneAlertCopy(
  title: 'DANGER ZONE',
  body:
      'You entered a place you marked as a danger zone. '
      'Turn around now, or open SOS before you decide anything.',
);
