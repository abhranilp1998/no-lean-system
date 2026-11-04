import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:native_geofence/native_geofence.dart';

import '../../recovery/domain/notification_policy.dart';
import '../../recovery/services/notification_service.dart';
import '../../recovery/services/recovery_state_store.dart';
import '../domain/background_zone_alert.dart';
import '../domain/danger_zone.dart';
import '../domain/zone_entry.dart';
import 'geofence_gateway.dart';
import 'zone_entry_inbox.dart';

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
    // ENTER + DWELL (plan P0-2): DWELL catches a missed ENTER; the initial
    // trigger fires at once when the user is already inside on arming.
    triggers: const {GeofenceEvent.enter, GeofenceEvent.dwell},
    iosSettings: const IosGeofenceSettings(initialTrigger: true),
    androidSettings: const AndroidGeofenceSettings(
      initialTriggers: {GeofenceEvent.enter},
      loiteringDelay: dwellDelay,
      notificationResponsiveness: responsiveness,
    ),
  );

  static const dwellDelay = Duration(minutes: 3);

  /// Wider early-warning ring around [zone]; ENTER only, no initial trigger
  /// (being near on arming is not news).
  static Geofence nearGeofenceFor(DangerZone zone) => Geofence(
    id: nearGeofenceIdForZone(zone),
    location: Location(latitude: zone.latitude, longitude: zone.longitude),
    radiusMeters: earlyWarningRadius(zone),
    triggers: const {GeofenceEvent.enter},
    iosSettings: const IosGeofenceSettings(initialTrigger: false),
    androidSettings: const AndroidGeofenceSettings(
      initialTriggers: {},
      notificationResponsiveness: responsiveness,
    ),
  );

  @override
  Future<void> sync(List<DangerZone> zones) async {
    await _init();
    final wanted = <String, Geofence>{
      for (final zone in zones) ...{
        geofenceIdForZone(zone): geofenceFor(zone),
        nearGeofenceIdForZone(zone): nearGeofenceFor(zone),
      },
    };
    for (final active in await _manager.getRegisteredGeofences()) {
      if (!active.id.startsWith(zoneGeofencePrefix) &&
          !active.id.startsWith(nearGeofencePrefix)) {
        continue;
      }
      final zone = wanted[active.id];
      final unchanged =
          zone != null &&
          active.radiusMeters == zone.radiusMeters &&
          active.triggers.length == zone.triggers.length &&
          active.location.latitude == zone.location.latitude &&
          active.location.longitude == zone.location.longitude;
      if (unchanged) {
        wanted.remove(active.id);
      } else {
        await _manager.removeGeofenceById(active.id);
      }
    }
    for (final geofence in wanted.values) {
      await _manager.createGeofence(geofence, zoneGeofenceTriggered);
    }
  }

  @override
  Future<void> clear() async {
    await _init();
    for (final id in await _manager.getRegisteredGeofenceIds()) {
      if (id.startsWith(zoneGeofencePrefix) ||
          id.startsWith(nearGeofencePrefix)) {
        await _manager.removeGeofenceById(id);
      }
    }
  }
}

/// Runs in a background isolate when Android reports a zone entry. Reads the
/// local state file only; nothing leaves the device.
@pragma('vm:entry-point')
Future<void> zoneGeofenceTriggered(GeofenceCallbackParams params) async {
  if (params.event != GeofenceEvent.enter &&
      params.event != GeofenceEvent.dwell) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  String? raw;
  try {
    raw = await FileRecoveryStateStore().read();
  } catch (_) {
    raw = null;
  }
  final now = DateTime.now();
  final ids = params.geofences.map((geofence) => geofence.id).toList();
  final near = backgroundNearAlert(rawState: raw, geofenceIds: ids);
  if (near != null && !ids.any((id) => id.startsWith(zoneGeofencePrefix))) {
    await NotificationService.instance.showZoneAlert(
      title: near.title,
      body: near.body,
      prefs: notificationPrefsFromRawState(raw),
    );
    return;
  }
  final copy = backgroundZoneAlert(rawState: raw, geofenceIds: ids, now: now);
  // Opt-in history: hand entries to the app instead of writing the state
  // file from this isolate.
  for (final entry
      in params.event == GeofenceEvent.dwell
          ? const <ZoneEntry>[]
          : backgroundZoneEntries(rawState: raw, geofenceIds: ids, now: now)) {
    try {
      await FileZoneEntryInbox().append(entry);
    } catch (_) {
      /* The alert still matters more than the log. */
    }
  }
  if (copy == null) return;
  await NotificationService.instance.showZoneAlert(
    title: copy.title,
    body: copy.body,
    prefs: notificationPrefsFromRawState(raw),
  );
}
