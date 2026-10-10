import 'danger_zone.dart';
import 'zone_presence.dart';

/// What the app currently knows about the device position.
enum PositionAvailability {
  /// Location access is granted but no fix has arrived yet.
  locating,

  /// A fix is available.
  fix,

  /// Location services are switched off on the device.
  locationOff,

  /// NO LEAN has no location permission.
  noPermission,
}

/// Text for the always-on "Position status" notification.
///
/// [stateKey] changes only on a real state change (availability, entering or
/// leaving a zone, privacy mode); coordinate and distance drift does not
/// change it, so [PositionStatusThrottle] can rate-limit those updates.
class PositionStatusText {
  const PositionStatusText({
    required this.title,
    required this.body,
    required this.stateKey,
  });

  final String title;
  final String body;
  final String stateKey;

  @override
  bool operator ==(Object other) =>
      other is PositionStatusText &&
      other.title == title &&
      other.body == body &&
      other.stateKey == stateKey;

  @override
  int get hashCode => Object.hash(title, body, stateKey);

  @override
  String toString() => 'PositionStatusText($title | $body | $stateKey)';
}

/// Neutral wording when "hide sensitive content" is on: no zone names, no
/// coordinates, no distances.
const neutralPositionTitle = 'NO LEAN // position active';
const neutralPositionBody = 'Open the app for details.';

/// Builds the position notification text. Pure, so it is unit-tested.
///
/// - Coordinates are rounded to 3 decimals (~110 m), enough for a glance.
/// - Inside a zone (distance to centre <= radius) the title reads
///   `INSIDE <zone>`; with several, the one whose centre is closest wins.
/// - Otherwise the body names the nearest zone and the distance to its edge.
/// - This is an indicator only: zone alerts keep their own presence tracker,
///   de-duplication and quiet-hours policy and are never affected by it.
PositionStatusText buildPositionStatusText({
  required PositionAvailability availability,
  required List<DangerZone> zones,
  required bool hideSensitive,
  LocationFix? fix,
}) {
  final effective = availability == PositionAvailability.fix && fix == null
      ? PositionAvailability.locating
      : availability;

  if (hideSensitive) {
    return PositionStatusText(
      title: neutralPositionTitle,
      body: neutralPositionBody,
      stateKey: 'hidden:${effective.name}',
    );
  }

  switch (effective) {
    case PositionAvailability.locationOff:
      return const PositionStatusText(
        title: 'Position: location off',
        body: 'Turn on device location to see your position.',
        stateKey: 'locationOff',
      );
    case PositionAvailability.noPermission:
      return const PositionStatusText(
        title: 'Position: no permission',
        body: 'Allow location for NO LEAN to see your position.',
        stateKey: 'noPermission',
      );
    case PositionAvailability.locating:
      return const PositionStatusText(
        title: 'Position: locating…',
        body: 'Waiting for the first location fix.',
        stateKey: 'locating',
      );
    case PositionAvailability.fix:
      break;
  }

  final here = fix!;
  final coords =
      '${here.latitude.toStringAsFixed(3)}, ${here.longitude.toStringAsFixed(3)}';
  final accuracy = here.accuracyMeters.isFinite
      ? ' // ±${here.accuracyMeters.round()} m'
      : '';

  DangerZone? inside;
  var insideDistance = double.infinity;
  DangerZone? nearest;
  var nearestEdge = double.infinity;
  for (final zone in zones) {
    final distance = zone.distanceTo(here.latitude, here.longitude);
    if (distance <= zone.radiusMeters) {
      if (distance < insideDistance) {
        inside = zone;
        insideDistance = distance;
      }
    } else {
      final edge = distance - zone.radiusMeters;
      if (edge < nearestEdge) {
        nearest = zone;
        nearestEdge = edge;
      }
    }
  }

  if (inside != null) {
    return PositionStatusText(
      title: 'INSIDE ${inside.name}',
      body: '$coords$accuracy',
      stateKey: 'inside:${inside.id}',
    );
  }
  return PositionStatusText(
    title: 'Position $coords',
    body: nearest == null
        ? 'No danger zones marked$accuracy'
        : 'Nearest: ${nearest.name} // ${formatPositionDistance(nearestEdge)} to edge$accuracy',
    stateKey: 'outside',
  );
}

/// `340 m`, `1.2 km`, `12 km`.
String formatPositionDistance(double meters) {
  if (!meters.isFinite || meters < 0) return '0 m';
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

/// Rate limit for the position notification: posts immediately on a state
/// change (see [PositionStatusText.stateKey]) and otherwise at most once per
/// [minInterval]. A post after the interval is allowed even with unchanged
/// text: it refreshes the notification's timeout and restores it if it was
/// swiped away.
class PositionStatusThrottle {
  PositionStatusThrottle({this.minInterval = const Duration(seconds: 15)});

  final Duration minInterval;
  String? _lastKey;
  DateTime? _lastAt;

  /// Returns whether to post now, and records the post when it does.
  bool shouldPost(PositionStatusText text, DateTime now) {
    final lastAt = _lastAt;
    final post =
        lastAt == null ||
        text.stateKey != _lastKey ||
        now.difference(lastAt) >= minInterval ||
        now.isBefore(lastAt); // Clock went backwards: don't stall.
    if (post) {
      _lastKey = text.stateKey;
      _lastAt = now;
    }
    return post;
  }

  /// Forget history, e.g. after the notification was cancelled.
  void reset() {
    _lastKey = null;
    _lastAt = null;
  }
}
