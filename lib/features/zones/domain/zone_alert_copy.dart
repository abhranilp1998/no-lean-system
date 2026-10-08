import 'package:intl/intl.dart';

import '../../recovery/domain/risk_window.dart';
import 'danger_zone.dart';

class ZoneAlertCopy {
  const ZoneAlertCopy({required this.title, required this.body});

  final String title;
  final String body;
}

/// Firm, data-backed copy for entering a danger zone. Only states facts the
/// user recorded: the zone, when they marked it, clean-since date, and whether
/// this is also their configured risk window.
ZoneAlertCopy buildZoneAlertCopy({
  required DangerZone zone,
  required DateTime now,
  DateTime? cleanSince,
  RiskWindow? riskWindow,
}) {
  final date = DateFormat('d MMM');
  final parts = <String>[
    'You marked ${zone.name} as a danger zone on ${date.format(zone.createdAt)}.',
    if (cleanSince != null) 'Clean since ${date.format(cleanSince)}.',
    if (riskWindow != null && riskWindow.contains(now))
      'You are also inside your ${riskWindow.label} risk window.',
    'Turn around now, or open SOS before you decide anything.',
  ];
  return ZoneAlertCopy(
    title: 'DANGER ZONE // ${zone.name.toUpperCase()}',
    body: parts.join(' '),
  );
}
