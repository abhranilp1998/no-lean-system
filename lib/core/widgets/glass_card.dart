import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.accent = cyan,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final Widget child;
  final Color accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(
          alpha: visuals.highContrast ? .97 : .86,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(
            alpha: visuals.accentOpacity(
              .26,
              minimum: visuals.highContrast ? .42 : .12,
            ),
          ),
          width: visuals.highContrast ? 1.35 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: visuals.glowOpacity(.07)),
            blurRadius: 24 * visuals.glowRadiusScale,
            spreadRadius: -3,
          ),
        ],
      ),
      child: child,
    );
  }
}
