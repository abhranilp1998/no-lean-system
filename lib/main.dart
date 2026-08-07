import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/no_lean_app.dart';

export 'app/no_lean_app.dart' show NoLeanApp;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  // Keep the device awake only during debug investigation sessions; releases
  // must respect the user's normal display timeout and battery settings.
  if (kDebugMode) {
    unawaited(WakelockPlus.enable());
  }

  runApp(const ProviderScope(child: NoLeanApp()));
}
