import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Picks the daily check-in time. Returns minutes after midnight, or null.
Future<int?> pickCheckInTime(BuildContext context, int initialMinutes) async {
  final selected = await showTimePicker(
    context: context,
    helpText: 'DAILY CHECK-IN TIME',
    initialTime: TimeOfDay(
      hour: initialMinutes ~/ 60,
      minute: initialMinutes % 60,
    ),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        timePickerTheme: TimePickerThemeData(
          backgroundColor: panel,
          dialBackgroundColor: panelRaised,
          dialHandColor: cyan,
          hourMinuteColor: cyan.withValues(alpha: .12),
          dayPeriodColor: magenta.withValues(alpha: .12),
        ),
      ),
      child: child!,
    ),
  );
  return selected == null ? null : selected.hour * 60 + selected.minute;
}
