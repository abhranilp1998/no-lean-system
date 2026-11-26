import 'package:flutter/material.dart';

import '../services/app_feedback.dart';
import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';
import 'hold_to_act.dart';

class GlowButton extends StatelessWidget {
  const GlowButton({
    required this.label,
    required this.onTap,
    required this.color,
    this.icon,
    this.onHold,
    this.onHoldStart,
    this.holdDuration,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;

  /// When set, a ~2 s hold runs this instead of [onTap]; a shorter press
  /// still runs [onTap]. Used by SOS buttons for hold-to-text.
  final VoidCallback? onHold;
  final VoidCallback? onHoldStart;
  final Duration? holdDuration;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    final button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: visuals.glowOpacity(.28)),
            blurRadius: 18 * visuals.glowRadiusScale,
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onHold == null
            ? () {
                AppFeedback.tap(strength: AppFeedbackStrength.strong);
                onTap();
              }
            : () {},
        icon: Icon(icon ?? Icons.arrow_forward, size: 18),
        label: Text(
          label,
          style: displayFont(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(
            alpha: visuals.accentOpacity(.16, minimum: .1),
          ),
          foregroundColor: color,
          side: BorderSide(
            color: color.withValues(
              alpha: visuals.accentOpacity(.72, minimum: .52),
            ),
            width: visuals.highContrast ? 1.5 : 1,
          ),
          minimumSize: const Size.fromHeight(54),
          enableFeedback: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
    if (onHold == null) return button;
    return HoldToAct(
      onTap: () {
        AppFeedback.tap(strength: AppFeedbackStrength.strong);
        onTap();
      },
      onHold: onHold!,
      onHoldStart: onHoldStart,
      duration: holdDuration ?? const Duration(milliseconds: 2000),
      color: color,
      child: button,
    );
  }
}
