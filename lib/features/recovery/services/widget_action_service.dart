import 'dart:async';

import 'package:flutter/services.dart';

class WidgetActionService {
  WidgetActionService._();

  static final instance = WidgetActionService._();
  static const _channel = MethodChannel('no_lean/widget_actions');
  static const supportedActions = {'sos', 'craving'};

  final _actions = StreamController<String>.broadcast();
  bool _initialized = false;

  Stream<String> get actionStream => _actions.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') _emit(call.arguments);
    });
    try {
      _emit(await _channel.invokeMethod<String>('consumeInitialAction'));
    } on PlatformException {
      // Interactive widgets are Android-only; app navigation still works.
    } on MissingPluginException {
      // Expected on tests and unsupported platforms.
    }
  }

  void _emit(Object? action) {
    if (action is String && supportedActions.contains(action)) {
      _actions.add(action);
    }
  }
}
