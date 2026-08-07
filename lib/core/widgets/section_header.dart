import 'package:flutter/material.dart';

import '../services/app_feedback.dart';
import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    required this.action,
    required this.onTap,
    super.key,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: eyebrowStyle.copyWith(color: visuals.secondaryTextColor),
        ),
        TextButton(
          onPressed: () {
            AppFeedback.selection();
            onTap();
          },
          style: TextButton.styleFrom(enableFeedback: false),
          child: Text(action, style: microStyle.copyWith(color: cyan)),
        ),
      ],
    );
  }
}
