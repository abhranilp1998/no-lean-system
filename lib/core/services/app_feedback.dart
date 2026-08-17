import 'dart:async';

import 'package:flutter/services.dart';

import 'feedback_preferences.dart';

enum AppFeedbackStrength { subtle, normal, strong }

/// One configuration point for tactile and optional system-sound feedback.
///
/// Call [configure] from the app root whenever persisted settings change, then
/// use the semantic methods from interactive widgets and workflows.
abstract final class AppFeedback {
  static const _channel = MethodChannel('no_lean/feedback');

  static bool _soundEnabled = false;
  static bool _vibrationEnabled = true;
  static int _effectIntensity = 1;
  static FeedbackSoundEffect _soundEffect = FeedbackSoundEffect.neonPulse;

  static void configure({
    required bool soundEnabled,
    required bool vibrationEnabled,
    required int effectIntensity,
    required FeedbackSoundEffect soundEffect,
  }) {
    _soundEnabled = soundEnabled;
    _vibrationEnabled = vibrationEnabled;
    _effectIntensity = effectIntensity.clamp(0, 3).toInt();
    _soundEffect = soundEffect;
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

  /// Lets the feedback submenu audition a tone before preferences are saved.
  static void previewSound(FeedbackSoundEffect effect) {
    unawaited(_emitSound(effect, SystemSoundType.click));
  }

  /// Lets the feedback submenu confirm vibration independently of its setting.
  static void previewVibration() {
    unawaited(_emitHaptic(AppFeedbackStrength.normal.index));
  }

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
    if (_vibrationEnabled) await _emitHaptic(strength);
    if (_soundEnabled) await _emitSound(_soundEffect, sound);
  }

  static Future<void> _emitHaptic(int strength) async {
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
  }

  static Future<void> _emitSound(
    FeedbackSoundEffect effect,
    SystemSoundType fallback,
  ) async {
    try {
      final played = await _channel.invokeMethod<bool>('play', {
        'effect': effect.name,
      });
      if (played == true) return;
    } on Object {
      // The custom tone bridge is Android-specific. Other targets fall back to
      // their platform UI sound so feedback still works.
    }
    try {
      await SystemSound.play(fallback);
    } on Object {
      // System sounds are not available on every Flutter target either.
    }
  }
}
