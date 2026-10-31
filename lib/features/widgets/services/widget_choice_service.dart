import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/fullscreen_widgets.dart';

/// A placed widget that can show a full-screen view.
class PlacedWidget {
  const PlacedWidget({required this.id, required this.kind, this.override});

  final int id;

  /// `medium` (4x2), `large` (4x3) or `full` (NO LEAN Full).
  final String kind;

  /// Per-widget choice; null follows the app-wide choice.
  final StretchedWidgetView? override;

  String get label => switch (kind) {
    'medium' => 'NO LEAN 4x2',
    'large' => 'NO LEAN 4x3',
    _ => 'NO LEAN Full',
  };
}

/// Per-widget overrides live on the device (widget ids are device-specific
/// and change on reinstall), so they are not in app state or backups.
class WidgetChoiceService {
  WidgetChoiceService({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel('no_lean/widget'),
      _enabled = enabled ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _enabled;

  Future<List<PlacedWidget>> placed() async {
    if (!_enabled) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('placedWidgets');
      return [
        for (final item in raw ?? const <Object?>[])
          if (item is Map && item['id'] is int)
            PlacedWidget(
              id: item['id'] as int,
              kind: item['kind']?.toString() ?? 'full',
              override: item['view'] == null
                  ? null
                  : StretchedWidgetView.fromName(item['view']),
            ),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<void> setOverride(int id, StretchedWidgetView? view) async {
    if (!_enabled) return;
    await _channel.invokeMethod<void>('setWidgetView', {
      'id': id,
      'view': view?.nativeName,
    });
  }
}
