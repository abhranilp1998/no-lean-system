import 'dart:async';

import 'package:flutter/services.dart';

enum AppFeedbackStrength { subtle, normal, strong }

/// One configuration point for tactile and optional system-sound feedback.
///
/// Call [configure] from the app root whenever persisted settings change, then
/// use the semantic methods from interactive widgets and workflows.
abstract final class AppFeedback {
  static bool _soundEnabled = false;
  static int _effectIntensity = 1;

  static void configure({
    required bool soundEnabled,
    required int effectIntensity,
  }) {
    _soundEnabled = soundEnabled;
    _effectIntensity = effectIntensity.clamp(0, 2).toInt();
  }

  static void selection() => _dispatch(AppFeedbackStrength.subtle);

  static void tap({AppFeedbackStrength strength = AppFeedbackStrength.normal}) {
    _dispatch(strength);
  }

  static void success() =>
      _dispatch(AppFeedbackStrength.normal, sound: SystemSoundType.click);

  static void warning() =>
      _dispatch(AppFeedbackStrength.strong, sound: SystemSoundType.alert);

  static void error() =>
      _dispatch(AppFeedbackStrength.strong, sound: SystemSoundType.alert);

  static void _dispatch(
    AppFeedbackStrength requested, {
    SystemSoundType sound = SystemSoundType.click,
  }) {
    final effectiveStrength = (requested.index + _effectIntensity - 1)
        .clamp(0, 2)
        .toInt();
    unawaited(_emit(effectiveStrength, sound));
  }

  static Future<void> _emit(int strength, SystemSoundType sound) async {
    try {
      switch (strength) {
        case 0:
          await HapticFeedback.selectionClick();
        case 1:
          await HapticFeedback.lightImpact();
        case 2:
          await HapticFeedback.heavyImpact();
      }
    } on Object {
      // Feedback is an enhancement; unsupported hardware must never block UI.
    }

    if (!_soundEnabled) return;
    try {
      await SystemSound.play(sound);
    } on Object {
      // System sounds are not available on every Flutter target.
    }
  }
}
