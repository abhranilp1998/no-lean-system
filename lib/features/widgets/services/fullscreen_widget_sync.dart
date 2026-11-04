import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../recovery/domain/recovery_event.dart';
import '../../zones/domain/danger_zone.dart';
import '../domain/fullscreen_widgets.dart';
import '../domain/garden.dart';
import '../presentation/garden_painter.dart';
import '../presentation/radar_painter.dart';
import 'widget_art.dart';

/// Renders bitmap art for the garden and radar widgets and hands the file
/// paths to the native widgets. Art is only redrawn when its inputs change.
class FullscreenWidgetSync {
  FullscreenWidgetSync({
    @visibleForTesting Future<Directory> Function()? directory,
    @visibleForTesting bool? enabled,
    @visibleForTesting this.widgets = enabledFullscreenWidgets,
  }) : _directory = directory ?? getApplicationSupportDirectory,
       _enabled = enabled ?? (!kIsWeb && Platform.isAndroid);

  static const channel = MethodChannel('no_lean/widget');
  static final instance = FullscreenWidgetSync();

  final Future<Directory> Function() _directory;
  final bool _enabled;
  final List<FullscreenWidget> widgets;
  String? _gardenKey;
  String? _radarKey;
  Future<void>? _running;

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> sync({
    required List<RecoveryEvent> events,
    required List<DangerZone> zones,
    int noteCount = 0,
    String stretchedView = 'auto',
    DateTime? now,
  }) async {
    if (!_enabled) return;
    // Serialise runs; the next call sees the newest state anyway.
    while (_running != null) {
      await _running;
    }
    final run = _sync(
      events,
      zones,
      now ?? DateTime.now(),
      noteCount,
      stretchedView,
    );
    _running = run;
    try {
      await run;
    } catch (_) {
      // Widget art is optional; recovery tracking never depends on it.
    } finally {
      _running = null;
    }
  }

  Future<Map<String, Object>?> _sync(
    List<RecoveryEvent> events,
    List<DangerZone> zones,
    DateTime now, [
    int noteCount = 0,
    String stretchedView = 'auto',
  ]) async {
    final dir = Directory('${(await _directory()).path}/widget_art');
    await dir.create(recursive: true);
    final args = <String, Object>{};
    if (widgets.contains(FullscreenWidget.garden)) {
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final garden = Garden.fromEvents(events, today);
      final next = garden.plusCleanDay(tomorrow);
      final key =
          '${dateKey(today)}|${garden.cleanTotal}|'
          '${garden.plants.map((p) => p.state.index).join()}';
      if (key != _gardenKey) {
        for (final (label, g) in [('today', garden), ('tomorrow', next)]) {
          for (final evening in [false, true]) {
            final png = await renderWidgetPng(
              gardenArtSize,
              (c, s) => paintGarden(c, s, g, evening: evening),
            );
            await File(
              '${dir.path}/garden_${label}_${evening ? 'evening' : 'day'}.png',
            ).writeAsBytes(png, flush: true);
          }
        }
        _gardenKey = key;
      }
      args['gardenDir'] = dir.path;
      args['gardenToday'] = dateKey(today);
      args['gardenTomorrow'] = dateKey(tomorrow);
    }
    if (widgets.contains(FullscreenWidget.dangerRadar)) {
      final key = jsonEncode([for (final z in zones) z.toJson()]);
      if (key != _radarKey) {
        final png = await renderWidgetPng(
          radarArtSize,
          (c, s) => paintRadar(c, s, zones),
        );
        await File('${dir.path}/radar.png').writeAsBytes(png, flush: true);
        _radarKey = key;
      }
      args['radarPath'] = '${dir.path}/radar.png';
      args['radarZones'] = zones.length;
    }
    // Only whether notes exist; never their text.
    args['hasNotes'] = noteCount > 0;
    args['stretchedView'] = stretchedView;
    await channel.invokeMethod<void>('art', args);
    return args;
  }

  /// Test hook: renders without the platform gate or channel errors hidden.
  @visibleForTesting
  Future<Map<String, Object>?> runOnce({
    required List<RecoveryEvent> events,
    required List<DangerZone> zones,
    required DateTime now,
    int noteCount = 0,
    String stretchedView = 'auto',
  }) => _sync(events, zones, now, noteCount, stretchedView);
}
