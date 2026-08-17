import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Runtime appearance values shared by the cyberpunk visual system.
///
/// Keeping these values in a [ThemeExtension] lets feature widgets react to
/// accessibility and effect settings without importing recovery state.
@immutable
class NoLeanVisuals extends ThemeExtension<NoLeanVisuals> {
  const NoLeanVisuals({
    required this.highContrast,
    required this.reduceMotion,
    required this.effectScale,
    required this.secondaryTextColor,
  });

  static const fallback = NoLeanVisuals(
    highContrast: false,
    reduceMotion: false,
    effectScale: 1,
    secondaryTextColor: Color(0xFF7B879E),
  );

  final bool highContrast;
  final bool reduceMotion;

  /// A normalized multiplier: calm is below 1, aggressive is above 1.
  final double effectScale;
  final Color secondaryTextColor;

  bool get ultraMode => effectScale >= 1.75;

  static NoLeanVisuals of(BuildContext context) =>
      Theme.of(context).extension<NoLeanVisuals>() ?? fallback;

  /// Scales accent borders, fills, scanlines, and other static effects.
  double accentOpacity(double base, {double minimum = 0}) {
    final contrastBoost = highContrast ? 1.2 : 1;
    return (base * effectScale * contrastBoost).clamp(minimum, 1.0).toDouble();
  }

  /// Scales bloom and chromatic glow. Reduced motion also softens bloom.
  double glowOpacity(double base, {double minimum = 0}) {
    final motionScale = reduceMotion ? .45 : 1;
    final contrastBoost = highContrast ? 1.12 : 1;
    return (base * effectScale * motionScale * contrastBoost)
        .clamp(minimum, 1.0)
        .toDouble();
  }

  double get glowRadiusScale =>
      effectScale * (reduceMotion ? .55 : 1) * (highContrast ? 1.08 : 1);

  Duration motionDuration(Duration duration) {
    if (reduceMotion) return Duration.zero;
    final speed = effectScale.clamp(.65, 1.8);
    return Duration(microseconds: (duration.inMicroseconds / speed).round());
  }

  @override
  NoLeanVisuals copyWith({
    bool? highContrast,
    bool? reduceMotion,
    double? effectScale,
    Color? secondaryTextColor,
  }) => NoLeanVisuals(
    highContrast: highContrast ?? this.highContrast,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    effectScale: effectScale ?? this.effectScale,
    secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
  );

  @override
  NoLeanVisuals lerp(covariant NoLeanVisuals? other, double t) {
    if (other == null) return this;
    return NoLeanVisuals(
      highContrast: t < .5 ? highContrast : other.highContrast,
      reduceMotion: t < .5 ? reduceMotion : other.reduceMotion,
      effectScale: lerpDouble(effectScale, other.effectScale, t) ?? effectScale,
      secondaryTextColor:
          Color.lerp(secondaryTextColor, other.secondaryTextColor, t) ??
          secondaryTextColor,
    );
  }
}
