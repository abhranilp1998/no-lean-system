import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class RiskWindowBanner extends StatelessWidget {
  const RiskWindowBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: red.withValues(alpha: .08),
        border: Border.all(color: red.withValues(alpha: .42)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: red, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'RISK WINDOW  /  17:30—20:00  /  STAY MOVING',
              style: microStyle.copyWith(color: red, letterSpacing: .7),
            ),
          ),
        ],
      ),
    );
  }
}
