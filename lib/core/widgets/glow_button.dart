import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(15),
      boxShadow: [
        BoxShadow(color: color.withValues(alpha: .28), blurRadius: 18),
      ],
    ),
    child: ElevatedButton.icon(
      onPressed: onTap,
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
        backgroundColor: color.withValues(alpha: .16),
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: .72)),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
  );
}
