import 'dart:async';

import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/services/location_service.dart';

class FakeLocationService implements LocationService {
  FakeLocationService({
    this.current = LocationAccess.whileInUse,
    this.onRequestForeground,
    this.onRequestBackground,
    this.fix,
  });

  LocationAccess current;
  LocationAccess? onRequestForeground;
  LocationAccess? onRequestBackground;
  LocationFix? fix;
  final controller = StreamController<LocationFix>.broadcast();
  int streamListens = 0;
  int settingsOpened = 0;

  @override
  Future<LocationAccess> access() async => current;

  @override
  Future<LocationFix?> currentFix() async => fix;

  @override
  Stream<LocationFix> fixes() {
    streamListens++;
    return controller.stream;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<LocationAccess> requestBackground() async =>
      current = onRequestBackground ?? current;

  @override
  Future<LocationAccess> requestForeground() async =>
      current = onRequestForeground ?? current;
}
