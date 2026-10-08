import 'dart:math' as math;

/// A user-defined place that should trigger an interrupt on entry.
///
/// Stored in the versioned recovery JSON (state v9+) and in JSON backups
/// (format 4+). Coordinates never leave the device.
class DangerZone {
  const DangerZone({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.createdAt,
  });

  static const minRadiusMeters = 100.0;
  static const maxRadiusMeters = 2000.0;
  static const defaultRadiusMeters = 200.0;
  static const maxNameLength = 40;

  /// Android allows 100 geofences per app; keep a wide safety margin.
  static const maxZones = 20;

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final DateTime createdAt;

  DangerZone copyWith({String? name, double? radiusMeters}) => DangerZone(
    id: id,
    name: name ?? this.name,
    latitude: latitude,
    longitude: longitude,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    createdAt: createdAt,
  )..validate();

  /// Throws [FormatException] when any field is out of range.
  void validate() {
    final trimmed = name.trim();
    if (id.trim().isEmpty) {
      throw const FormatException('Danger zone ID is missing.');
    }
    if (trimmed.isEmpty || trimmed.length > maxNameLength) {
      throw const FormatException(
        'Danger zone names must be 1–$maxNameLength characters.',
      );
    }
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw const FormatException('Danger zone latitude is invalid.');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw const FormatException('Danger zone longitude is invalid.');
    }
    if (!radiusMeters.isFinite ||
        radiusMeters < minRadiusMeters ||
        radiusMeters > maxRadiusMeters) {
      throw const FormatException(
        'Danger zone radius must be 100–2000 metres.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
    'createdAt': createdAt.toIso8601String(),
  };

  factory DangerZone.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Danger zone must be an object.');
    }
    final id = json['id'];
    final name = json['name'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final radius = json['radiusMeters'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (id is! String ||
        name is! String ||
        latitude is! num ||
        longitude is! num ||
        radius is! num ||
        createdAt == null) {
      throw const FormatException('Danger zone is missing required fields.');
    }
    return DangerZone(
      id: id,
      name: name.trim(),
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      radiusMeters: radius.toDouble(),
      createdAt: createdAt,
    )..validate();
  }

  /// Decodes a stored list, rejecting duplicates and too many zones.
  static List<DangerZone> decodeList(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('Danger zones must be a list.');
    }
    if (value.length > maxZones) {
      throw const FormatException('Too many danger zones.');
    }
    final ids = <String>{};
    final zones = <DangerZone>[];
    for (final item in value) {
      final zone = DangerZone.fromJson(item);
      if (!ids.add(zone.id)) {
        throw FormatException('Duplicate danger zone ID: ${zone.id}');
      }
      zones.add(zone);
    }
    return zones;
  }

  /// Great-circle distance in metres (haversine; accurate to well under 1%
  /// at geofence scales).
  double distanceTo(double lat, double lng) =>
      haversineMeters(latitude, longitude, lat, lng);
}

double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadius * math.asin(math.min(1, math.sqrt(a)));
}
