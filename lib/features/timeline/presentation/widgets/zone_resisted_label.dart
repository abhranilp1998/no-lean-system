import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../recovery/domain/recovery_event.dart';

/// History label for a clean check-in that answered a danger-zone follow-up.
/// Null for every other event.
(String, IconData, Color)? zoneResistedDetails(RecoveryEvent event) {
  if (event.type != RecoveryEventType.cleanCheckIn ||
      event.metadata['zoneResisted'] != true) {
    return null;
  }
  final name = event.metadata['zoneName'];
  return (
    name is String ? 'ZONE RESISTED // $name' : 'ZONE RESISTED',
    Icons.shield_moon_outlined,
    toxic,
  );
}
