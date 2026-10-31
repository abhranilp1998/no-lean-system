import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/fullscreen_widgets.dart';

/// A widget the user already has on their home screen.
class PlacedWidget {
  const PlacedWidget({required this.id, required this.kind, this.override});

  final int id;

  /// `small`, `medium`, `large`, `full`, or an older single-view kind
  /// (`tonight`, `garden`, `evening`, `map`, `note`).
  final String kind;

  /// Per-widget choice. Null means: classic look (small/medium/large) or
  /// the app-wide choice (Full).
  final StretchedWidgetView? override;

  bool get isClassic => const {'small', 'medium', 'large'}.contains(kind);
  bool get isFull => kind == 'full';

  /// Older single-view widgets keep working but are no longer offered.
  bool get isLegacy => !isClassic && !isFull;

  /// The small 2x1 has no room for a full-screen view.
  bool get canChooseView => isFull || kind == 'medium' || kind == 'large';

  String get label => switch (kind) {
    'small' => 'NO LEAN 2x1',
    'medium' => 'NO LEAN 4x2',
    'large' => 'NO LEAN 4x3',
    'full' => 'NO LEAN Full',
    'tonight' => 'NO LEAN Tonight (older widget)',
    'garden' => 'NO LEAN Garden (older widget)',
    'evening' => 'NO LEAN Evening (older widget)',
    'map' => 'NO LEAN Map (older widget)',
    'note' => 'NO LEAN Note (older widget)',
    _ => 'NO LEAN widget',
  };
}

/// The widgets offered in the launcher picker, in the app's Widgets page.
enum WidgetKind {
  small('small', 'NO LEAN 2x1', 'Clean time at a glance. Tap to open.'),
  medium(
    'medium',
    'NO LEAN 4x2',
    'Clean time, next milestone and SOS, log craving, log relapse buttons.',
  ),
  large(
    'large',
    'NO LEAN 4x3',
    'Everything in 4x2 plus a bigger counter and more room for progress.',
  ),
  full(
    'full',
    'NO LEAN Full',
    'One big widget. Pick what it shows below: garden, evening, tonight, '
        'ride it out, map or note.',
  );

  const WidgetKind(this.native, this.title, this.description);
  final String native;
  final String title;
  final String description;
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
              override: _view(item['view']),
            ),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Asks the launcher to add [kind]. False when the launcher can't pin
  /// widgets (then the page shows manual steps).
  Future<bool> pin(WidgetKind kind) async {
    if (!_enabled) return false;
    try {
      return await _channel.invokeMethod<bool>('pinWidget', {
            'kind': kind.native,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> setOverride(int id, StretchedWidgetView? view) async {
    if (!_enabled) return;
    await _channel.invokeMethod<void>('setWidgetView', {
      'id': id,
      'view': view?.nativeName,
    });
  }

  static StretchedWidgetView? _view(Object? raw) {
    for (final v in StretchedWidgetView.values) {
      if (v.nativeName == raw) return v;
    }
    return null;
  }
}
