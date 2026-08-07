import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      border: Border.all(color: color.withValues(alpha: .45)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: microStyle.copyWith(color: color, fontSize: 9, letterSpacing: .7),
    ),
  );
}
