import 'dart:async';

import '../domain/danger_zone.dart';
import '../domain/zone_presence.dart';
import '../services/location_service.dart';

/// Foreground-only distance checks while NO LEAN is open.
///
/// Listens to a battery-friendly location stream (balanced accuracy, 50 m
/// distance filter) only while [setActive] is true, i.e. the app is resumed,
/// monitoring is enabled and at least one zone exists. Nothing runs while the
/// app is in the background; that is the job of OS geofencing.
class ZoneMonitor {
  ZoneMonitor({
    required LocationService location,
    required this.onEnter,
    ZonePresenceTracker? tracker,
  }) : _location = location,
       _tracker = tracker ?? ZonePresenceTracker();

  final LocationService _location;
  final ZonePresenceTracker _tracker;
  final void Function(DangerZone zone) onEnter;

  StreamSubscription<LocationFix>? _subscription;
  List<DangerZone> _zones = const [];
  bool _starting = false;

  bool get isRunning => _subscription != null;

  /// Starts or stops monitoring. Safe to call on every rebuild.
  Future<void> setActive(bool active, List<DangerZone> zones) async {
    _zones = zones;
    if (!active || zones.isEmpty) {
      await stop();
      return;
    }
    if (_subscription != null || _starting) return;
    _starting = true;
    try {
      final access = await _location.access();
      if (access != LocationAccess.whileInUse &&
          access != LocationAccess.always) {
        return;
      }
      _subscription = _location.fixes().listen(
        handleFix,
        onError: (Object _) => stop(),
        cancelOnError: true,
      );
    } finally {
      _starting = false;
    }
  }

  void handleFix(LocationFix fix) {
    for (final zone in _tracker.update(_zones, fix)) {
      onEnter(zone);
    }
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
