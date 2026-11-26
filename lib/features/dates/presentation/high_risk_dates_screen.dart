import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/save_action.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_provider.dart';
import '../domain/bundled_dates.dart';
import '../domain/high_risk_dates.dart';
import 'high_risk_plan_sheet.dart';

class HighRiskDatesScreen extends ConsumerWidget {
  const HighRiskDatesScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HighRiskDatesScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final upcoming = recovery.upcomingHighRiskDates(limit: 8);
    final payday = recovery.paydayDay;
    final weekday = recovery.worstWeekday;
    final dateFormat = DateFormat('EEE d MMM y');

    return Scaffold(
      backgroundColor: panel,
      appBar: AppBar(title: const Text('High-risk dates')),
      body: ListView(
        key: const Key('high-risk-dates-screen'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text('PLAN AHEAD', style: eyebrowStyle.copyWith(color: cyan)),
          const SizedBox(height: 6),
          Text(
            'Festival days, your dates, payday, and a harder weekday from your logs.',
            style: displayFont(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'A reminder three days ahead asks you to write a short plan. Festival days after 2030 will need a list update. Eid can move a day with moon sighting — add your own if a listed day is off.',
            style: TextStyle(fontSize: 12, color: muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const Key('high-risk-reminders-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Date reminders',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Three days ahead, after quiet hours. On by default.',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
            value: recovery.highRiskDateReminders,
            activeThumbColor: cyan,
            onChanged: (value) => saveAction(
              context,
              () => ref.read(recoveryProvider).setHighRiskDateReminders(value),
            ),
          ),
          const SizedBox(height: 8),
          if (upcoming.isNotEmpty) ...[
            const Text(
              'UPCOMING',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: .6,
                color: muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final item in upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  accent: item.daysUntil <= highRiskLeadDays ? cyan : muted,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.title),
                    subtitle: Text(
                      '${dateFormat.format(item.date)}'
                      '${item.hasPlan ? ' · plan saved' : ''}',
                    ),
                    trailing: TextButton(
                      onPressed: () =>
                          showHighRiskPlanSheet(context, ref, item),
                      child: Text(item.hasPlan ? 'SEE PLAN' : 'PLAN'),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
          const Text(
            'PAYDAY',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: .6,
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          GlassCard(
            child: ListTile(
              key: const Key('high-risk-payday'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Monthly payday'),
              subtitle: Text(
                payday == null
                    ? 'Off. Set the day you usually get paid.'
                    : 'Day $payday each month. Short months use the last day.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editPayday(context, ref, payday),
            ),
          ),
          if (weekday != null) ...[
            const SizedBox(height: 16),
            const Text(
              'HARDER WEEKDAY',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: .6,
                color: muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            GlassCard(
              child: SwitchListTile(
                key: const Key('high-risk-weekday-nudges'),
                contentPadding: EdgeInsets.zero,
                title: Text('${weekdayNames[weekday]}s from your logs'),
                subtitle: const Text(
                  'One reminder three days before the next one. Needs a clear pattern in your log.',
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
                value: recovery.weekdayNudges,
                activeThumbColor: cyan,
                onChanged: (value) => saveAction(
                  context,
                  () => ref.read(recoveryProvider).setWeekdayNudges(value),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'YOUR DATES',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .6,
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                key: const Key('high-risk-add-date'),
                onPressed: () => _addCustomDate(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('ADD'),
              ),
            ],
          ),
          if (recovery.customHighRiskDates.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Birthdays, an anniversary of a loss, exam or result days.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          for (final custom in recovery.customHighRiskDates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(custom.name),
                  subtitle: Text(_customSubtitle(custom)),
                  trailing: IconButton(
                    key: Key('high-risk-remove-${custom.id}'),
                    tooltip: 'Remove',
                    onPressed: () => saveAction(
                      context,
                      () => ref
                          .read(recoveryProvider)
                          .removeCustomHighRiskDate(custom.id),
                    ),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'FESTIVAL LIST',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: .6,
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final festival in bundledFestivals)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                accent: recovery.disabledBundledDateIds.contains(festival.id)
                    ? muted
                    : cyan,
                child: SwitchListTile(
                  key: Key('high-risk-festival-${festival.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(festival.name),
                  subtitle: Text(
                    festival.blurb,
                    style: const TextStyle(fontSize: 11.5, color: muted),
                  ),
                  value: !recovery.disabledBundledDateIds.contains(festival.id),
                  activeThumbColor: cyan,
                  onChanged: (value) => saveAction(
                    context,
                    () => ref
                        .read(recoveryProvider)
                        .setBundledFestivalEnabled(festival.id, value),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _customSubtitle(CustomHighRiskDate custom) {
    if (custom.once != null) {
      return '${custom.kind.label} · ${DateFormat('d MMM y').format(custom.once!)}';
    }
    return '${custom.kind.label} · every ${DateFormat('d MMM').format(DateTime(2026, custom.month!, custom.day!))}';
  }
}

Future<void> _editPayday(
  BuildContext context,
  WidgetRef ref,
  int? current,
) async {
  var selected = current ?? 1;
  final picked = await showDialog<int?>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Monthly payday'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Day of the month you usually get paid. Months that are shorter use the last day.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 12),
            DropdownButton<int>(
              key: const Key('high-risk-payday-day'),
              value: selected,
              isExpanded: true,
              items: [
                for (var day = 1; day <= 31; day++)
                  DropdownMenuItem(value: day, child: Text('Day $day')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => selected = value);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: const Text('TURN OFF'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            key: const Key('high-risk-payday-save'),
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('SAVE'),
          ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  await saveAction(
    context,
    () => ref.read(recoveryProvider).setPaydayDay(picked == 0 ? null : picked),
  );
}

Future<void> _addCustomDate(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<_NewCustomDate>(
    context: context,
    builder: (context) => const _AddCustomDateDialog(),
  );
  if (result == null || !context.mounted) return;
  await saveAction(
    context,
    () => ref
        .read(recoveryProvider)
        .addCustomHighRiskDate(
          name: result.name,
          kind: result.kind,
          month: result.month,
          day: result.day,
          once: result.once,
        ),
  );
}

class _NewCustomDate {
  const _NewCustomDate({
    required this.name,
    required this.kind,
    this.month,
    this.day,
    this.once,
  });

  final String name;
  final CustomDateKind kind;
  final int? month;
  final int? day;
  final DateTime? once;
}

class _AddCustomDateDialog extends StatefulWidget {
  const _AddCustomDateDialog();

  @override
  State<_AddCustomDateDialog> createState() => _AddCustomDateDialogState();
}

class _AddCustomDateDialogState extends State<_AddCustomDateDialog> {
  final _name = TextEditingController();
  var _kind = CustomDateKind.birthday;
  var _annual = true;
  var _month = DateTime.now().month;
  var _day = DateTime.now().day;
  DateTime? _once;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _name.text.trim();
    if (trimmed.isEmpty) return;
    if (!_annual && _once == null) return;
    Navigator.pop(
      context,
      _NewCustomDate(
        name: trimmed,
        kind: _kind,
        month: _annual ? _month : null,
        day: _annual ? _day : null,
        once: _annual ? null : _once,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a date'),
      content: SingleChildScrollView(
        child: Column(
          key: const Key('high-risk-add-date-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('high-risk-custom-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 10),
            DropdownButton<CustomDateKind>(
              key: const Key('high-risk-custom-kind'),
              value: _kind,
              isExpanded: true,
              items: [
                for (final value in CustomDateKind.values)
                  DropdownMenuItem(value: value, child: Text(value.label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _kind = value);
              },
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeats every year'),
              value: _annual,
              onChanged: (value) => setState(() => _annual = value),
            ),
            if (_annual)
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<int>(
                      key: const Key('high-risk-custom-month'),
                      value: _month,
                      isExpanded: true,
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              DateFormat('MMMM').format(DateTime(2026, m)),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _month = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<int>(
                      key: const Key('high-risk-custom-day'),
                      value: _day,
                      isExpanded: true,
                      items: [
                        for (var d = 1; d <= 31; d++)
                          DropdownMenuItem(value: d, child: Text('$d')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _day = value);
                      },
                    ),
                  ),
                ],
              )
            else
              TextButton(
                key: const Key('high-risk-custom-once'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _once ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) setState(() => _once = picked);
                },
                child: Text(
                  _once == null
                      ? 'Pick a date'
                      : DateFormat('d MMM y').format(_once!),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          key: const Key('high-risk-custom-save'),
          onPressed: _save,
          child: const Text('ADD'),
        ),
      ],
    );
  }
}
