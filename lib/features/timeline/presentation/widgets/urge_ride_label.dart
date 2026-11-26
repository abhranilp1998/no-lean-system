import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../cravings/domain/urge_ride.dart';
import '../../../recovery/domain/recovery_event.dart';

/// History label for a finished ride-it-out check. Null for every other event.
(String, IconData, Color)? urgeRideDetails(RecoveryEvent event) {
  final label = urgeRideHistoryLabel(event);
  if (label == null) return null;
  return (label, Icons.waves, cyan);
}
