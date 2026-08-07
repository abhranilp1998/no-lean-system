import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';

class ProgressHeatMap extends StatelessWidget {
  const ProgressHeatMap({required this.cleanDays, super.key});

  final Map<String, bool> cleanDays;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: List.generate(30, (index) {
        final day = today.subtract(Duration(days: 29 - index));
        final status = cleanDays[dateKey(day)];
        final color = status == true
            ? cyan.withValues(alpha: .85)
            : status == false
            ? red.withValues(alpha: .65)
            : panelRaised;
        final stateLabel = status == true
            ? 'clean'
            : status == false
            ? 'relapse recorded'
            : 'not marked';

        return Semantics(
          label: '${_spokenDate(day)}, $stateLabel',
          child: Tooltip(
            message: '${_shortDate(day)} · $stateLabel',
            child: Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: status == null
                      ? muted.withValues(alpha: .08)
                      : color.withValues(alpha: .85),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}';

String _spokenDate(DateTime value) =>
    '${value.day}/${value.month}/${value.year}';
