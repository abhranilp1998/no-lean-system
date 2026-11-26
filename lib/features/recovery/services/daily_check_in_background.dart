import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import '../domain/daily_check_in.dart';
import 'check_in_inbox.dart';

/// Runs in a background isolate when Okay or Used is tapped on the daily
/// check-in, without opening the app. It only appends to the local inbox;
/// the app writes the real events on next load or resume with the tap time
/// as occurredAt. Nothing leaves the device.
@pragma('vm:entry-point')
Future<void> dailyCheckInBackground(NotificationResponse response) async {
  final answer = checkInAnswerFor(response.actionId);
  if (answer == null) return;
  final at = DateTime.now();
  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await FileCheckInInbox().append(
      CheckInEntry(id: const Uuid().v4(), answer: answer, at: at),
    );
  } catch (_) {
    /* Nothing more to do in the background; the notification is gone. */
  }
}
