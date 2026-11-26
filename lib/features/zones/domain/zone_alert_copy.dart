import 'package:intl/intl.dart';

import '../../recovery/domain/if_then_plan.dart';
import '../../recovery/domain/risk_window.dart';
import 'danger_zone.dart';

class ZoneAlertCopy {
  const ZoneAlertCopy({
    required this.title,
    required this.body,
    this.plans = const [],
    this.screenBody,
  });

  final String title;
  final String body;

  /// The user's own if-then plans for this zone, shown on the alert screen.
  final List<IfThenPlan> plans;

  /// The body without the plan line, for the alert screen, which shows the
  /// plans in their own card. Null means [body] as is.
  final String? screenBody;

  String get screenText => screenBody ?? body;
}

/// Firm, data-backed copy for entering a danger zone. Only states facts the
/// user recorded: the zone, when they marked it, clean-since date, and whether
/// this is also their configured risk window.
ZoneAlertCopy buildZoneAlertCopy({
  required DangerZone zone,
  required DateTime now,
  DateTime? cleanSince,
  RiskWindow? riskWindow,
  List<IfThenPlan> plans = const [],
}) {
  final zonePlans = plansForZone(plans, zone.id);
  final date = DateFormat('d MMM');
  final parts = <String>[
    'You marked ${zone.name} as a danger zone on ${date.format(zone.createdAt)}.',
    if (cleanSince != null) 'Clean since ${date.format(cleanSince)}.',
    if (riskWindow != null && riskWindow.contains(now))
      'You are also inside your ${riskWindow.label} risk window.',
    'Turn around now, or open SOS before you decide anything.',
  ];
  final screenBody = parts.join(' ');
  if (zonePlans.isNotEmpty) {
    parts.insert(parts.length - 1, planNotificationLine(zonePlans.first));
  }
  return ZoneAlertCopy(
    title: 'DANGER ZONE // ${zone.name.toUpperCase()}',
    body: parts.join(' '),
    plans: zonePlans,
    screenBody: zonePlans.isEmpty ? null : screenBody,
  );
}
