import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../recovery/domain/recovery_event.dart';
import '../../domain/heat_map_data.dart';

Color heatMapColor(HeatMapMode mode) => switch (mode) {
  HeatMapMode.days => cyan,
  HeatMapMode.count => magenta,
  HeatMapMode.amount => red,
  HeatMapMode.cost => toxic,
  HeatMapMode.stress => purple,
};

/// 30-day grid. DAYS (default) shows clean vs relapse; the other modes
/// shade each day by how much was logged.
class ProgressHeatMap extends StatelessWidget {
  const ProgressHeatMap({
    required this.cleanDays,
    this.mode = HeatMapMode.days,
    this.events = const [],
    super.key,
  });

  final Map<String, bool> cleanDays;
  final HeatMapMode mode;
  final List<RecoveryEvent> events;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final values = mode == HeatMapMode.days
        ? const <String, double>{}
        : heatMapValues(mode, events);
    final days = [
      for (var index = 0; index < 30; index++)
        DateTime(today.year, today.month, today.day - (29 - index)),
    ];
    final top = mode == HeatMapMode.stress
        ? 5.0
        : days
              .map((day) => values[dateKey(day)] ?? 0)
              .fold<double>(0, (a, b) => a > b ? a : b);
    final accent = heatMapColor(mode);
    return Wrap(
      key: ValueKey('heatmap-grid-${mode.name}'),
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final day in days)
          if (mode == HeatMapMode.days)
            _daysCell(day)
          else
            _valueCell(day, values[dateKey(day)], top, accent),
      ],
    );
  }

  Widget _daysCell(DateTime day) {
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
    return _Cell(
      semantics: '${_spokenDate(day)}, $stateLabel',
      tooltip: '${_shortDate(day)} · $stateLabel',
      color: color,
      outlined: status != null,
    );
  }

  Widget _valueCell(DateTime day, double? value, double top, Color accent) {
    final shown = value == null ? 'nothing logged' : mode.format(value);
    final strength = value == null || top <= 0
        ? 0.0
        : (.25 + .75 * (value / top)).clamp(.25, 1.0);
    return _Cell(
      semantics: '${_spokenDate(day)}, ${mode.label.toLowerCase()} $shown',
      tooltip: '${_shortDate(day)} · $shown',
      color: value == null ? panelRaised : accent.withValues(alpha: strength),
      outlined: value != null,
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.semantics,
    required this.tooltip,
    required this.color,
    required this.outlined,
  });

  final String semantics;
  final String tooltip;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    child: Tooltip(
      message: tooltip,
      child: Container(
        width: 19,
        height: 19,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: outlined
                ? color.withValues(alpha: .85)
                : muted.withValues(alpha: .08),
          ),
        ),
      ),
    ),
  );
}

/// Mode chips + grid + weekday breakdown, in one stateful card body.
class HeatMapPanel extends StatefulWidget {
  const HeatMapPanel({
    required this.cleanDays,
    required this.events,
    super.key,
  });

  final Map<String, bool> cleanDays;
  final List<RecoveryEvent> events;

  @override
  State<HeatMapPanel> createState() => _HeatMapPanelState();
}

class _HeatMapPanelState extends State<HeatMapPanel> {
  var _mode = HeatMapMode.days;

  @override
  Widget build(BuildContext context) {
    final accent = heatMapColor(_mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final mode in HeatMapMode.values)
              ChoiceChip(
                key: ValueKey('heatmap-mode-${mode.name}'),
                label: Text(mode.label, style: const TextStyle(fontSize: 10)),
                selected: _mode == mode,
                selectedColor: heatMapColor(mode).withValues(alpha: .25),
                onSelected: (_) => setState(() => _mode = mode),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _mode.description.toUpperCase(),
          style: microStyle.copyWith(color: accent),
        ),
        const SizedBox(height: 12),
        ProgressHeatMap(
          cleanDays: widget.cleanDays,
          mode: _mode,
          events: widget.events,
        ),
        const SizedBox(height: 14),
        WeekdayCard(
          summary: weekdaySummary(_mode, widget.events, now: DateTime.now()),
        ),
      ],
    );
  }
}

/// Weekday bars for the selected mode over the last 12 weeks, with the
/// peak day highlighted once there is enough data.
class WeekdayCard extends StatelessWidget {
  const WeekdayCard({required this.summary, super.key});

  final WeekdaySummary summary;

  @override
  Widget build(BuildContext context) {
    final mode = summary.mode;
    final accent = heatMapColor(mode);
    final peak = summary.peak;
    final top = summary.stats
        .map((s) => s.value)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final what = mode == HeatMapMode.days
        ? 'relapses'
        : mode.label.toLowerCase();
    return Container(
      key: const ValueKey('weekday-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BY WEEKDAY // LAST 12 WEEKS',
            style: microStyle.copyWith(color: accent),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final stat in summary.stats)
                  Expanded(
                    child: Semantics(
                      label:
                          '${stat.label}: ${stat.days == 0 ? 'nothing' : mode.format(stat.value)}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: top <= 0 ? 2 : 2 + 40 * stat.value / top,
                            decoration: BoxDecoration(
                              color: peak?.weekday == stat.weekday
                                  ? accent
                                  : accent.withValues(alpha: .35),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stat.label,
                            style: microStyle.copyWith(
                              fontSize: 8.5,
                              color: peak?.weekday == stat.weekday
                                  ? accent
                                  : muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            key: const ValueKey('weekday-peak'),
            peak == null
                ? summary.dataDays == 0
                      ? 'Nothing logged in this mode yet.'
                      : 'LOW DATA // ${summary.dataDays} day${summary.dataDays == 1 ? '' : 's'} logged. A peak day needs 5+ and a clear leader.'
                : 'PEAK: ${peak.label} // ${mode.format(peak.value)}$what across ${peak.days} day${peak.days == 1 ? '' : 's'}. Plan that day first.',
            style: const TextStyle(fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}

String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}';

String _spokenDate(DateTime value) =>
    '${value.day}/${value.month}/${value.year}';
