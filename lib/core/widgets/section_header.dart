import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title, style: eyebrowStyle.copyWith(color: muted)),
      TextButton(
        onPressed: onTap,
        child: Text(action, style: microStyle.copyWith(color: cyan)),
      ),
    ],
  );
}
