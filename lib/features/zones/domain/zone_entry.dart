import 'danger_zone.dart';

/// One recorded zone entry. Deliberately no coordinates: the zone name and
/// the time are the whole record (privacy by design).
class ZoneEntry {
  const ZoneEntry({
    required this.zoneId,
    required this.zoneName,
    required this.at,
    required this.source,
  });

  factory ZoneEntry.of(DangerZone zone, DateTime at, String source) =>
      ZoneEntry(zoneId: zone.id, zoneName: zone.name, at: at, source: source);

  /// Tolerant decode for the background inbox; null when unreadable.
  static ZoneEntry? tryDecode(Object? json) {
    if (json is! Map) return null;
    final id = json['zoneId'];
    final name = json['zoneName'];
    final at = DateTime.tryParse('${json['at']}');
    final source = json['source'];
    if (id is! String || name is! String || at == null) return null;
    return ZoneEntry(
      zoneId: id,
      zoneName: name,
      at: at,
      source: source is String ? source : 'background',
    );
  }

  final String zoneId;
  final String zoneName;
  final DateTime at;

  /// `app` (in-app monitor) or `background` (OS geofence).
  final String source;

  Map<String, Object> toJson() => {
    'zoneId': zoneId,
    'zoneName': zoneName,
    'at': at.toIso8601String(),
    'source': source,
  };

  /// Event metadata: name and source only, never a location.
  Map<String, Object> get metadata => {
    'zoneId': zoneId,
    'zoneName': zoneName,
    'source': source,
  };
}

/// The in-app monitor and the OS geofence can both report one visit; entries
/// for the same zone this close together are one entry.
const zoneEntryDedupWindow = Duration(minutes: 15);
