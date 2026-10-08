import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:native_geofence/native_geofence.dart';

import '../../recovery/services/notification_service.dart';
import '../../recovery/services/recovery_state_store.dart';
import '../domain/background_zone_alert.dart';
import '../domain/danger_zone.dart';
import 'geofence_gateway.dart';

/// OS geofencing via Android's GeofencingClient. No continuous GPS: the OS
/// batches location from its own providers. Enter-only triggers and a relaxed
/// notification responsiveness keep it battery-friendly.
class NativeGeofenceGateway implements GeofenceGateway {
  NativeGeofenceGateway();

  static const responsiveness = Duration(minutes: 2);
  bool _initialized = false;

  NativeGeofenceManager get _manager => NativeGeofenceManager.instance;

  Future<void> _init() async {
    if (_initialized) return;
    await _manager.initialize();
    _initialized = true;
  }

  static Geofence geofenceFor(DangerZone zone) => Geofence(
    id: geofenceIdForZone(zone),
    location: Location(latitude: zone.latitude, longitude: zone.longitude),
    radiusMeters: zone.radiusMeters,
    triggers: const {GeofenceEvent.enter},
    iosSettings: const IosGeofenceSettings(initialTrigger: true),
    androidSettings: const AndroidGeofenceSettings(
      initialTriggers: {GeofenceEvent.enter},
      notificationResponsiveness: responsiveness,
    ),
  );

  @override
  Future<void> sync(List<DangerZone> zones) async {
    await _init();
    final wanted = {for (final zone in zones) geofenceIdForZone(zone): zone};
    for (final active in await _manager.getRegisteredGeofences()) {
      if (!active.id.startsWith(zoneGeofencePrefix)) continue;
      final zone = wanted[active.id];
      final unchanged =
          zone != null &&
          active.radiusMeters == zone.radiusMeters &&
          active.location.latitude == zone.latitude &&
          active.location.longitude == zone.longitude;
      if (unchanged) {
        wanted.remove(active.id);
      } else {
        await _manager.removeGeofenceById(active.id);
      }
    }
    for (final zone in wanted.values) {
      await _manager.createGeofence(geofenceFor(zone), zoneGeofenceTriggered);
    }
  }

  @override
  Future<void> clear() async {
    await _init();
    for (final id in await _manager.getRegisteredGeofenceIds()) {
      if (id.startsWith(zoneGeofencePrefix)) {
        await _manager.removeGeofenceById(id);
      }
    }
  }
}

/// Runs in a background isolate when Android reports a zone entry. Reads the
/// local state file only; nothing leaves the device.
@pragma('vm:entry-point')
Future<void> zoneGeofenceTriggered(GeofenceCallbackParams params) async {
  if (params.event != GeofenceEvent.enter) return;
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  String? raw;
  try {
    raw = await FileRecoveryStateStore().read();
  } catch (_) {
    raw = null;
  }
  final copy = backgroundZoneAlert(
    rawState: raw,
    geofenceIds: params.geofences.map((geofence) => geofence.id),
    now: DateTime.now(),
  );
  if (copy == null) return;
  await NotificationService.instance.showZoneAlert(
    title: copy.title,
    body: copy.body,
  );
}
