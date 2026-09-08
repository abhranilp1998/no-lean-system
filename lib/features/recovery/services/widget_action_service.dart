import 'dart:async';

import 'package:flutter/services.dart';

class WidgetActionService {
  WidgetActionService._();

  static final instance = WidgetActionService._();
  static const _channel = MethodChannel('no_lean/widget_actions');
  static const supportedActions = {'sos', 'craving', 'relapse'};

  final _actions = StreamController<String>.broadcast();
  bool _initialized = false;
  bool _draining = false;

  Stream<String> get actionStream => _actions.stream;

  Future<void> initialize() async {
    if (!_initialized) {
      _initialized = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onAction') _emit(call.arguments);
        if (call.method == 'actionsAvailable') await _drain();
      });
    }
    await _drain();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      // The shell subscribes before draining; native code retains actions until
      // this ready handshake, including intents delivered during startup.
      while (true) {
        final actions = await _channel.invokeListMethod<String>('drainActions');
        if (actions == null || actions.isEmpty) break;
        for (final action in actions) {
          _emit(action);
        }
      }
    } on PlatformException {
      // Interactive widgets are Android-only; app navigation still works.
    } on MissingPluginException {
      // Expected on tests and unsupported platforms.
    } finally {
      _draining = false;
    }
  }

  void _emit(Object? action) {
    if (action is String && supportedActions.contains(action)) {
      _actions.add(action);
    }
  }
}
