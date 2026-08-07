import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppDialog extends StatelessWidget {
  const AppDialog({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: cyan.withValues(alpha: .3)),
    ),
    title: Text(
      title,
      style: displayFont(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    content: child,
  );
}
