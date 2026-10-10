import '../domain/danger_zone.dart';

/// Registers danger zones with the OS geofencing service.
///
/// The production implementation wraps `native_geofence`; tests use a fake.
abstract interface class GeofenceGateway {
  /// Replace all registered geofences with [zones].
  Future<void> sync(List<DangerZone> zones);

  /// Remove every geofence registered by this app.
  Future<void> clear();
}

class NoopGeofenceGateway implements GeofenceGateway {
  const NoopGeofenceGateway();

  @override
  Future<void> clear() async {}

  @override
  Future<void> sync(List<DangerZone> zones) async {}
}
