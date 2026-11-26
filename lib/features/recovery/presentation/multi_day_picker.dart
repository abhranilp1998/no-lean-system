import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/multi_day_log.dart';
import 'relapse_log_sheet.dart' show showRelapseTimePicker;

/// What the multi-day picker returns: the picked days and one time used
/// for all of them (each day's time can still be changed afterwards).
class MultiDayPick {
  const MultiDayPick({
    required this.days,
    required this.hour,
    required this.minute,
  });

  final List<DateTime> days;
  final int hour;
  final int minute;

  List<MultiDaySlot> slots(DateTime now) =>
      buildMultiDaySlots(days, now: now, hour: hour, minute: minute);
}

/// Calendar for choosing several past days at once. Future days cannot be
/// picked. Returns null when cancelled.
Future<MultiDayPick?> showMultiDayPicker(
  BuildContext context, {
  Iterable<DateTime> initialDays = const [],
  int initialHour = multiDayDefaultHour,
  int initialMinute = multiDayDefaultMinute,
  DateTime? now,
}) => showDialog<MultiDayPick>(
  context: context,
  builder: (_) => MultiDayPickerDialog(
    initialDays: initialDays,
    initialHour: initialHour,
    initialMinute: initialMinute,
    now: now,
  ),
);

class MultiDayPickerDialog extends StatefulWidget {
  const MultiDayPickerDialog({
    this.initialDays = const [],
    this.initialHour = multiDayDefaultHour,
    this.initialMinute = multiDayDefaultMinute,
    this.now,
    super.key,
  });

  final Iterable<DateTime> initialDays;
  final int initialHour;
  final int initialMinute;

  /// Fixed clock for tests and screenshots.
  final DateTime? now;

  @override
  State<MultiDayPickerDialog> createState() => _MultiDayPickerDialogState();
}

class _MultiDayPickerDialogState extends State<MultiDayPickerDialog> {
  late final DateTime _now = widget.now ?? DateTime.now();
  late final Set<DateTime> _selected = {
    for (final d in widget.initialDays)
      if (isPickableDay(d, now: _now)) dayOnly(d),
  };
  late DateTime _month = DateTime(_now.year, _now.month);
  late int _hour = widget.initialHour;
  late int _minute = widget.initialMinute;

  bool get _canGoForward =>
      DateTime(_month.year, _month.month + 1).isAfter(dayOnly(_now)) == false;
  bool get _canGoBack => _month.isAfter(DateTime(2000));

  void _toggle(DateTime day) => setState(() {
    if (!_selected.remove(day)) _selected.add(day);
  });

  void _pickLast(int count) => setState(() {
    _selected
      ..clear()
      ..addAll(lastDays(count, now: _now));
    _month = DateTime(_now.year, _now.month);
  });

  Future<void> _pickTime() async {
    final time = await showRelapseTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
      title: 'TIME FOR EACH DAY',
    );
    if (time != null && mounted) {
      setState(() {
        _hour = time.hour;
        _minute = time.minute;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    final tooMany = count > multiDayMaxDays;
    final time = DateFormat.jm().format(DateTime(2000, 1, 1, _hour, _minute));
    return Dialog(
      key: const ValueKey('multi-day-picker'),
      backgroundColor: panel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cyan.withValues(alpha: .45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'PICK THE DAYS',
                style: displayFont(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: cyan,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Missed a few days? Tap each day it happened. You will describe them once, and every day is saved as its own entry you can change later.',
                style: TextStyle(height: 1.4, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ActionChip(
                    key: const ValueKey('multi-day-last-3'),
                    label: const Text('LAST 3 DAYS'),
                    onPressed: () => _pickLast(3),
                  ),
                  ActionChip(
                    key: const ValueKey('multi-day-last-7'),
                    label: const Text('LAST 7 DAYS'),
                    onPressed: () => _pickLast(7),
                  ),
                  ActionChip(
                    key: const ValueKey('multi-day-clear'),
                    label: const Text('CLEAR'),
                    onPressed: count == 0
                        ? null
                        : () => setState(_selected.clear),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('multi-day-prev-month'),
                    tooltip: 'Previous month',
                    onPressed: _canGoBack
                        ? () => setState(
                            () => _month = DateTime(
                              _month.year,
                              _month.month - 1,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat.yMMMM().format(_month).toUpperCase(),
                      textAlign: TextAlign.center,
                      style: eyebrowStyle.copyWith(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('multi-day-next-month'),
                    tooltip: 'Next month',
                    onPressed: _canGoForward
                        ? () => setState(
                            () => _month = DateTime(
                              _month.year,
                              _month.month + 1,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              _MonthGrid(
                month: _month,
                now: _now,
                selected: _selected,
                onToggle: _toggle,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('multi-day-time'),
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text('TIME FOR EACH DAY · $time'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Not sure of the time? Leave it. You can change any single day before saving or later from History.',
                style: TextStyle(color: muted, fontSize: 10.5, height: 1.35),
              ),
              if (tooMany)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Up to $multiDayMaxDays days at a time. Save these, then add the rest.',
                    key: ValueKey('multi-day-too-many'),
                    style: TextStyle(color: red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('multi-day-use'),
                onPressed: count == 0 || tooMany
                    ? null
                    : () => Navigator.pop(
                        context,
                        MultiDayPick(
                          days: _selected.toList()..sort(),
                          hour: _hour,
                          minute: _minute,
                        ),
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: cyan,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(
                  count == 0
                      ? 'PICK AT LEAST ONE DAY'
                      : 'USE $count ${count == 1 ? 'DAY' : 'DAYS'}',
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.now,
    required this.selected,
    required this.onToggle,
  });

  final DateTime month;
  final DateTime now;
  final Set<DateTime> selected;
  final ValueChanged<DateTime> onToggle;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month).weekday - 1; // Mon first
    final today = dayOnly(now);
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final cells = <Widget>[
      for (final w in weekdays) Center(child: Text(w, style: microStyle)),
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        _DayCell(
          day: DateTime(month.year, month.month, d),
          isToday: DateTime(month.year, month.month, d) == today,
          enabled: isPickableDay(
            DateTime(month.year, month.month, d),
            now: now,
          ),
          selected: selected.contains(DateTime(month.year, month.month, d)),
          onTap: onToggle,
        ),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool enabled;
  final bool selected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label:
          '${DateFormat.yMMMMEEEEd().format(day)}${selected ? ', selected' : ''}${enabled ? '' : ', not available'}',
      child: InkWell(
        key: ValueKey('multi-day-cell-$key'),
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? () => onTap(day) : null,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? cyan.withValues(alpha: .85) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isToday
                  ? toxic
                  : selected
                  ? cyan
                  : muted.withValues(alpha: enabled ? .35 : .1),
            ),
          ),
          child: ExcludeSemantics(
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected
                    ? Colors.black
                    : enabled
                    ? Colors.white
                    : muted.withValues(alpha: .4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
