import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: panel.withValues(alpha: .86),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: accent.withValues(alpha: .26)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: .07),
          blurRadius: 24,
          spreadRadius: -3,
        ),
      ],
    ),
    child: child,
  );
}
