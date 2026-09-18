import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class RiskWindowBanner extends StatelessWidget {
  const RiskWindowBanner({
    required this.windowLabel,
    required this.lockArmed,
    super.key,
  });

  final String windowLabel;
  final bool lockArmed;

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
              'RISK WINDOW / $windowLabel / ${lockArmed ? 'HOLD LOCK ARMED' : 'STAY MOVING'}',
              style: microStyle.copyWith(color: red, letterSpacing: .7),
            ),
          ),
        ],
      ),
    );
  }
}
