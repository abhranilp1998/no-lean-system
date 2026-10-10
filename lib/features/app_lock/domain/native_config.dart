// The configuration NO LEAN hands to the native enforcement service. Pure,
// so what the service will enforce is unit-tested.

import '../../recovery/domain/risk_window.dart';
import '../../zones/domain/danger_zone.dart';
import 'locked_app.dart';
import 'never_lockable.dart';

/// Builds the JSON the Android service reads (`AppLockConfig.kt`). The
/// service only ever sees package names, the schedule, zone circles (kept
/// on the device) and notification privacy; never history.
Map<String, Object?> buildNativeAppLockConfig({
  required AppLockPolicy policy,
  required RiskWindow riskWindow,
  required List<DangerZone> zones,
  required bool hideSensitive,
}) {
  final window = policy.effectiveWindow(riskWindow);
  final packages = policy.enabledPackages;
  return {
    'version': 1,
    'enabled': policy.armed,
    'packages': packages.toList()..sort(),
    'labels': {
      for (final app in policy.apps)
        if (packages.contains(app.packageName)) app.packageName: app.label,
    },
    'paymentPackages': [
      for (final app in policy.apps)
        if (app.paymentApp && packages.contains(app.packageName))
          app.packageName,
    ],
    'neverLockable': neverLockablePackages.toList()..sort(),
    'schedule': policy.schedule.name,
    'windowStart': window?.startMinutes,
    'windowEnd': window?.endMinutes,
    'lockInsideDangerZones': policy.lockInsideDangerZones,
    'zones': policy.lockInsideDangerZones
        ? [
            for (final zone in zones)
              {
                'id': zone.id,
                'name': zone.name,
                'latitude': zone.latitude,
                'longitude': zone.longitude,
                'radiusMeters': zone.radiusMeters,
              },
          ]
        : const [],
    'hideSensitive': hideSensitive,
  };
}
