import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: visuals.accentOpacity(.12)),
        border: Border.all(
          color: color.withValues(
            alpha: visuals.accentOpacity(.45, minimum: .32),
          ),
          width: visuals.highContrast ? 1.35 : 1,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: microStyle.copyWith(
          color: color,
          fontSize: 9,
          fontWeight: visuals.highContrast ? FontWeight.w800 : FontWeight.w500,
          letterSpacing: .7,
        ),
      ),
    );
  }
}
