import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/no_lean_app.dart';

export 'app/no_lean_app.dart' show NoLeanApp;

/// TEST BRANCH ONLY (`test/device-debug-all-open-prs-2026-11-27`).
/// Keeps the screen awake for this device-debug session. Override with
/// `--dart-define=NL_DEVICE_DEBUG=false` if needed.
const bool kDeviceDebugSession = bool.fromEnvironment(
  'NL_DEVICE_DEBUG',
  defaultValue: true,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  if (kDeviceDebugSession) {
    unawaited(WakelockPlus.enable());
    debugPrint('NL.Debug: wakelock on');
  }

  runApp(const ProviderScope(child: NoLeanApp()));
}
