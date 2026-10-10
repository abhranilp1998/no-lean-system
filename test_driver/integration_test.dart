import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves `binding.takeScreenshot` captures to $SCREENSHOT_DIR (default
/// build/screens) on the host.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'build/screens';
    final file = File('$dir/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
