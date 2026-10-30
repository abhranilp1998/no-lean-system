import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/widgets/domain/fullscreen_widgets.dart';
import 'package:no_lean/features/widgets/services/fullscreen_widget_sync.dart';
import 'package:no_lean/features/zones/domain/danger_zone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every pack widget is enabled for everyone for now', () {
    expect(enabledFullscreenWidgets, FullscreenWidget.values);
  });

  test('renders garden and radar PNGs and hands paths to the widget', () async {
    final dir = await Directory.systemTemp.createTemp('art');
    addTearDown(() => dir.delete(recursive: true));
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FullscreenWidgetSync.channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FullscreenWidgetSync.channel, null),
    );
    final sync = FullscreenWidgetSync(
      directory: () async => dir,
      enabled: true,
    );
    final zones = [
      DangerZone.fromJson({
        'id': 'a',
        'name': 'Somewhere',
        'latitude': 22.57,
        'longitude': 88.36,
        'radiusMeters': 300,
        'createdAt': '2026-10-01T00:00:00.000',
      }),
    ];
    final args = (await sync.runOnce(
      events: [
        RecoveryEvent.create(
          type: RecoveryEventType.recoveryStart,
          timestamp: DateTime(2026, 10, 20),
        ),
      ],
      zones: zones,
      now: DateTime(2026, 10, 30, 19),
    ))!;
    expect(args['gardenToday'], '2026-10-30');
    expect(args['gardenTomorrow'], '2026-10-31');
    expect(args['radarZones'], 1);
    // Notes: only whether any exist, never their text.
    expect(args['hasNotes'], isFalse);
    for (final name in [
      'garden_today_day',
      'garden_today_evening',
      'garden_tomorrow_day',
      'garden_tomorrow_evening',
      'radar',
    ]) {
      final bytes = File('${dir.path}/widget_art/$name.png').readAsBytesSync();
      expect(bytes.sublist(1, 4), 'PNG'.codeUnits, reason: name);
    }
    expect(calls.single.method, 'art');
  });

  test('disabled off Android: no rendering, no channel call', () async {
    final sync = FullscreenWidgetSync(
      directory: () async => throw StateError('should not render'),
      enabled: false,
    );
    await sync.sync(events: const [], zones: const []);
  });
}
