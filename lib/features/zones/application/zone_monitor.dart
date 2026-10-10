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
    DateTime Function()? now,
  }) : _location = location,
       _tracker = tracker ?? ZonePresenceTracker(),
       _now = now ?? DateTime.now;

  final LocationService _location;
  final ZonePresenceTracker _tracker;
  final void Function(DangerZone zone) onEnter;
  final DateTime Function() _now;
  static const maxFixAge = Duration(minutes: 2);

  StreamSubscription<LocationFix>? _subscription;
  List<DangerZone> _zones = const [];
  bool _starting = false;
  int _generation = 0;
  DateTime? _latestFixAt;

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
    final generation = ++_generation;
    _latestFixAt = null;
    try {
      final access = await _location.access();
      if (generation != _generation) return;
      if (access != LocationAccess.whileInUse &&
          access != LocationAccess.always) {
        return;
      }
      _subscription = _location.fixes().listen(
        (fix) {
          if (generation == _generation) handleFix(fix);
        },
        onError: (Object _) {
          if (generation == _generation) unawaited(stop());
        },
        cancelOnError: true,
      );
      // A balanced stream can stay silent while the device is stationary.
      // Request a fresh fix on open/resume, just as the Locate me button does.
      unawaited(_readCurrentFix(generation));
    } catch (_) {
      if (generation == _generation) await stop();
    } finally {
      if (generation == _generation) _starting = false;
    }
  }

  Future<void> _readCurrentFix(int generation) async {
    try {
      final fix = await _location.currentFix();
      if (generation == _generation && _subscription != null && fix != null) {
        handleFix(fix);
      }
    } catch (_) {
      // Keep the stream alive if the one-shot GPS request times out or fails.
    }
  }

  void handleFix(LocationFix fix) {
    final age = _now().difference(fix.at);
    if (age > maxFixAge ||
        age < const Duration(minutes: -1) ||
        (_latestFixAt != null && fix.at.isBefore(_latestFixAt!))) {
      return;
    }
    _latestFixAt = fix.at;
    for (final zone in _tracker.update(_zones, fix)) {
      onEnter(zone);
    }
  }

  Future<void> stop() async {
    // Invalidate pending access/current-fix work before awaiting cancellation.
    _generation++;
    _starting = false;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
