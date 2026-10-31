import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/zones/services/zone_test_trigger.dart';

void main() {
  test('test zone uses ~150 m radius and a clear name', () {
    expect(testZoneRadiusMeters, 150);
    expect(testZoneName, contains('TEST'));
  });
}
