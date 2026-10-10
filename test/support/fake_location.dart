import 'dart:async';

import 'package:no_lean/features/zones/domain/zone_presence.dart';
import 'package:no_lean/features/zones/services/location_service.dart';

class FakeLocationService implements LocationService {
  FakeLocationService({
    this.current = LocationAccess.whileInUse,
    this.onRequestForeground,
    this.onRequestBackground,
    this.fix,
    this.accessResult,
    this.currentFixResult,
  });

  LocationAccess current;
  LocationAccess? onRequestForeground;
  LocationAccess? onRequestBackground;
  LocationFix? fix;
  Future<LocationAccess> Function()? accessResult;
  Future<LocationFix?> Function()? currentFixResult;
  final controller = StreamController<LocationFix>.broadcast();
  int streamListens = 0;
  int settingsOpened = 0;
  int currentFixRequests = 0;

  @override
  Future<LocationAccess> access() async =>
      accessResult == null ? current : await accessResult!();

  @override
  Future<LocationFix?> currentFix() async {
    currentFixRequests++;
    return currentFixResult == null ? fix : await currentFixResult!();
  }

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
