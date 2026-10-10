import 'danger_zone.dart';

/// One location fix from any source (foreground stream or geofence callback).
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.at,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime at;
}

/// Decides when a fix counts as *entering* a zone.
///
/// - Fixes less accurate than the zone radius (or [maxAccuracyMeters]) are
///   ignored so a coarse fix cannot raise a false alarm.
/// - Exit needs the fix to be [exitMarginMeters] (or its accuracy, whichever
///   is larger) beyond the radius, so GPS jitter at the edge does not flap.
/// - A zone alerts at most once per [realertAfter], even across re-entries.
class ZonePresenceTracker {
  ZonePresenceTracker({
    this.maxAccuracyMeters = 150,
    this.exitMarginMeters = 30,
    this.realertAfter = const Duration(minutes: 30),
  });

  final double maxAccuracyMeters;
  final double exitMarginMeters;
  final Duration realertAfter;

  final _inside = <String>{};
  final _lastAlert = <String, DateTime>{};

  Set<String> get insideZoneIds => Set.unmodifiable(_inside);

  /// Returns zones that should alert for this fix (newly entered and not
  /// alerted recently). Removed zones are forgotten.
  List<DangerZone> update(List<DangerZone> zones, LocationFix fix) {
    final ids = zones.map((zone) => zone.id).toSet();
    _inside.removeWhere((id) => !ids.contains(id));
    _lastAlert.removeWhere((id, _) => !ids.contains(id));

    final alerts = <DangerZone>[];
    for (final zone in zones) {
      final accuracy = fix.accuracyMeters.isFinite ? fix.accuracyMeters : 1e9;
      if (accuracy > maxAccuracyMeters || accuracy > zone.radiusMeters) {
        continue;
      }
      final distance = zone.distanceTo(fix.latitude, fix.longitude);
      final wasInside = _inside.contains(zone.id);
      if (!wasInside && distance <= zone.radiusMeters) {
        _inside.add(zone.id);
        final last = _lastAlert[zone.id];
        if (last == null || fix.at.difference(last) >= realertAfter) {
          _lastAlert[zone.id] = fix.at;
          alerts.add(zone);
        }
      } else if (wasInside &&
          distance >
              zone.radiusMeters +
                  (accuracy > exitMarginMeters ? accuracy : exitMarginMeters)) {
        _inside.remove(zone.id);
      }
    }
    return alerts;
  }
}
