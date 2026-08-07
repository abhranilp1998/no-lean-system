import 'package:flutter/material.dart';

import '../services/app_feedback.dart';
import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';

class GlowButton extends StatelessWidget {
  const GlowButton({
    required this.label,
    required this.onTap,
    required this.color,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return DecoratedBox(
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
        onPressed: () {
          AppFeedback.tap(strength: AppFeedbackStrength.strong);
          onTap();
        },
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
  }
}
