import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/zones/services/zone_test_trigger.dart';

void main() {
  test('test zone uses ~150 m radius and a clear name', () {
    expect(testZoneRadiusMeters, 150);
    expect(testZoneName, contains('TEST'));
  });

  test('trigger is debug-only: hidden in release builds', () {
    expect(zoneTestTriggerEnabled(debug: false), isFalse);
    expect(zoneTestTriggerEnabled(debug: true), isTrue);
    expect(zoneTestTriggerEnabled(), kDebugMode);
  });
}
