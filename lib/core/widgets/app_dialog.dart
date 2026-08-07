import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/no_lean_visuals.dart';

class AppDialog extends StatelessWidget {
  const AppDialog({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: cyan.withValues(
            alpha: visuals.accentOpacity(
              .3,
              minimum: visuals.highContrast ? .6 : .2,
            ),
          ),
          width: visuals.highContrast ? 1.5 : 1,
        ),
      ),
      title: Text(
        title,
        style: displayFont(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      content: child,
    );
  }
}
