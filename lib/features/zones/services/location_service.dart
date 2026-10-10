import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/zone_presence.dart';

enum LocationAccess {
  /// Location services are switched off on the device.
  serviceDisabled,
  denied,

  /// Denied with "don't ask again"; only system settings can grant it.
  deniedForever,
  whileInUse,
  always,
}

/// Device location behind an interface so zone logic is testable.
abstract interface class LocationService {
  Future<LocationAccess> access();

  /// Requests foreground ("while in use") location.
  Future<LocationAccess> requestForeground();

  /// Requests "allow all the time". On Android 11+ this routes the user to
  /// system settings; the returned value reflects what was granted.
  Future<LocationAccess> requestBackground();

  Future<LocationFix?> currentFix();

  /// Battery-friendly stream: balanced accuracy, 50 m distance filter.
  Stream<LocationFix> fixes();

  Future<void> openSettings();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  static LocationAccess _map(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always => LocationAccess.always,
        LocationPermission.whileInUse => LocationAccess.whileInUse,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => LocationAccess.denied,
      };

  @override
  Future<LocationAccess> access() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceDisabled;
      }
      return _map(await Geolocator.checkPermission());
    } catch (_) {
      return LocationAccess.denied;
    }
  }

  @override
  Future<LocationAccess> requestForeground() async {
    try {
      final current = await access();
      if (current != LocationAccess.denied) return current;
      return _map(await Geolocator.requestPermission());
    } catch (_) {
      return LocationAccess.denied;
    }
  }

  @override
  Future<LocationAccess> requestBackground() async {
    try {
      final foreground = await requestForeground();
      if (foreground != LocationAccess.whileInUse) return foreground;
      // geolocator asks for ACCESS_BACKGROUND_LOCATION when it is declared
      // and foreground access is already granted.
      return _map(await Geolocator.requestPermission());
    } catch (_) {
      return LocationAccess.denied;
    }
  }

  static LocationFix _fix(Position position) => LocationFix(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy,
    at: position.timestamp,
  );

  @override
  Future<LocationFix?> currentFix() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return _fix(position);
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        return last == null ? null : _fix(last);
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Stream<LocationFix> fixes() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 50,
    ),
  ).map(_fix);

  @override
  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      /* Nothing else to do; the UI explains how to grant access. */
    }
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);
