import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/services/save_action.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/dose_units.dart';
import '../../recovery/domain/money_saved.dart';
import 'savings_goal_photo.dart';

/// Shown by [showSpendDialog]; also usable in widget tests.
class SpendSetupDialog extends StatefulWidget {
  const SpendSetupDialog({
    required this.currency,
    required this.spendPerBottle,
    required this.usualDailyMl,
    required this.dailySpend,
    required this.bottleMl,
    required this.subtractOtherCosts,
    super.key,
  });

  final AppCurrency currency;
  final double? spendPerBottle;
  final double? usualDailyMl;
  final double dailySpend;
  final double bottleMl;
  final bool subtractOtherCosts;

  @override
  State<SpendSetupDialog> createState() => _SpendSetupDialogState();
}

class SpendDraft {
  const SpendDraft({
    required this.currency,
    this.spendPerBottle,
    this.usualDailyMl,
    this.dailySpend,
    required this.subtractOtherCosts,
  });

  final AppCurrency currency;
  final double? spendPerBottle;
  final double? usualDailyMl;
  final double? dailySpend;
  final bool subtractOtherCosts;
}

class _SpendSetupDialogState extends State<SpendSetupDialog> {
  late AppCurrency _currency = widget.currency;
  late final TextEditingController _perBottle;
  late final TextEditingController _usual;
  late final TextEditingController _daily;
  late DoseUnit _usualUnit;
  late bool _subtract = widget.subtractOtherCosts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _perBottle = TextEditingController(
      text: widget.spendPerBottle != null && widget.spendPerBottle! > 0
          ? widget.spendPerBottle!.round().toString()
          : '',
    );
    final usual = widget.usualDailyMl;
    if (usual != null && usual > 0 && usual % widget.bottleMl == 0) {
      _usualUnit = DoseUnit.bottle;
      _usual = TextEditingController(
        text: formatAmount(usual / widget.bottleMl),
      );
    } else if (usual != null && usual > 0) {
      _usualUnit = DoseUnit.ml;
      _usual = TextEditingController(text: formatAmount(usual));
    } else {
      _usualUnit = DoseUnit.bottle;
      _usual = TextEditingController();
    }
    // Only prefill the direct daily total when there is no breakdown, so
    // a derived figure does not look like a separate number to edit.
    final hasBreakdown =
        widget.spendPerBottle != null &&
        widget.spendPerBottle! > 0 &&
        widget.usualDailyMl != null &&
        widget.usualDailyMl! > 0;
    _daily = TextEditingController(
      text: !hasBreakdown && widget.dailySpend > 0
          ? widget.dailySpend.round().toString()
          : '',
    );
  }

  @override
  void dispose() {
    _perBottle.dispose();
    _usual.dispose();
    _daily.dispose();
    super.dispose();
  }

  SpendDraft? _draft() {
    final per = parseAmount(_perBottle.text);
    final usualEntered = parseAmount(_usual.text);
    final daily = parseAmount(_daily.text);
    if (per != null && (per < 0 || per > maxRelapseCost)) {
      _error = 'Enter a price of 0 or more.';
      return null;
    }
    double? usualMl;
    if (usualEntered != null) {
      if (usualEntered <= 0) {
        _error = 'Usual amount should be greater than zero.';
        return null;
      }
      usualMl = toMl(usualEntered, _usualUnit, bottleMl: widget.bottleMl);
      if (usualMl == null || usualMl > maxDoseMl) {
        _error = 'Usual amount is too large.';
        return null;
      }
    }
    if (daily != null && (daily < 0 || daily > maxRelapseCost)) {
      _error = 'Enter a daily total of 0 or more.';
      return null;
    }
    final derived = typicalDailySpend(
      spendPerBottle: per,
      usualDailyMl: usualMl,
      bottleMl: widget.bottleMl,
    );
    if ((derived == null || derived <= 0) && (daily == null || daily <= 0)) {
      // Saving zeros is allowed: it clears the counter.
    }
    _error = null;
    return SpendDraft(
      currency: _currency,
      spendPerBottle: per != null && per > 0 ? per : null,
      usualDailyMl: usualMl != null && usualMl > 0 ? usualMl : null,
      dailySpend: daily,
      subtractOtherCosts: _subtract,
    );
  }

  void _save() {
    final draft = _draft();
    if (draft == null) {
      setState(() {});
      return;
    }
    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _draft();
    final derived = typicalDailySpend(
      spendPerBottle: preview?.spendPerBottle,
      usualDailyMl: preview?.usualDailyMl,
      bottleMl: widget.bottleMl,
    );
    final rate = derived ?? preview?.dailySpend ?? 0;
    return AppDialog(
      title: 'TYPICAL SPEND',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Used to count money kept since your clean timer started. '
                'Amounts stay on this device.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 14),
              Text('CURRENCY', style: microStyle.copyWith(color: muted)),
              const SizedBox(height: 6),
              DropdownButtonFormField<AppCurrency>(
                key: const ValueKey('spend-currency'),
                initialValue: _currency,
                isExpanded: true,
                selectedItemBuilder: (context) => [
                  for (final c in AppCurrency.supported)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${c.symbol} ${c.code}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                items: [
                  for (final c in AppCurrency.supported)
                    DropdownMenuItem(
                      value: c,
                      child: Text(
                        '${c.symbol}  ${c.code}  ·  ${c.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _currency = value);
                },
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('spend-per-bottle'),
                controller: _perBottle,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  prefixText: '${_currency.symbol}  ',
                  labelText: 'Spend per ${formatMl(widget.bottleMl)} bottle',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('spend-usual-amount'),
                controller: _usual,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Usual amount per day',
                  suffixText: _usualUnit.label,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final unit in const [DoseUnit.bottle, DoseUnit.ml])
                    ChoiceChip(
                      key: ValueKey('spend-unit-${unit.name}'),
                      label: Text(unit.label.toUpperCase()),
                      selected: _usualUnit == unit,
                      onSelected: (_) => setState(() => _usualUnit = unit),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('spend-daily-total'),
                controller: _daily,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  prefixText: '${_currency.symbol}  ',
                  labelText: 'Or a daily total',
                  helperText: derived != null && derived > 0
                      ? 'From your bottle figures: ${_currency.format(derived)} / day'
                      : 'Use this if you would rather not think in bottles.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                key: const ValueKey('spend-subtract-other'),
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Subtract logged spend on other days',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'If a slip that did not reset your clean timer has a cost, take it off the total.',
                  style: TextStyle(color: muted, fontSize: 11, height: 1.35),
                ),
                value: _subtract,
                onChanged: (v) => setState(() => _subtract = v),
              ),
              if (rate > 0) ...[
                const SizedBox(height: 6),
                Text(
                  key: const ValueKey('spend-preview'),
                  'A usual day is ${_currency.format(rate)}.',
                  style: const TextStyle(color: toxic, fontSize: 13),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: red, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('spend-save'),
                  onPressed: _save,
                  child: const Text('SAVE TYPICAL SPEND'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSpendDialog(BuildContext context, WidgetRef ref) async {
  final recovery = ref.read(recoveryProvider);
  final draft = await showDialog<SpendDraft>(
    context: context,
    builder: (_) => SpendSetupDialog(
      currency: recovery.currency,
      spendPerBottle: recovery.spendPerBottle,
      usualDailyMl: recovery.usualDailyMl,
      dailySpend: recovery.dailySpend,
      bottleMl: recovery.bottleMl,
      subtractOtherCosts: recovery.subtractOtherCosts,
    ),
  );
  if (draft == null || !context.mounted) return;
  if (!await saveAction(
    context,
    () => ref
        .read(recoveryProvider)
        .updateMoneySavedSettings(
          currency: draft.currency,
          spendPerBottle: draft.spendPerBottle,
          usualDailyMl: draft.usualDailyMl,
          dailySpend: draft.dailySpend,
          subtractOtherCosts: draft.subtractOtherCosts,
        ),
  )) {
    return;
  }
  if (context.mounted) {
    AppNotice.show(
      context,
      'TYPICAL SPEND UPDATED.',
      type: AppNoticeType.success,
    );
  }
}

/// Result wrapper so "clear" is distinct from cancelling the dialog.
class GoalDialogResult {
  const GoalDialogResult(this.goal);
  final SavingsGoal? goal;
}

class SavingsGoalDialog extends StatefulWidget {
  const SavingsGoalDialog({required this.currency, this.initial, super.key});

  final SavingsGoal? initial;
  final AppCurrency currency;

  @override
  State<SavingsGoalDialog> createState() => _SavingsGoalDialogState();
}

class _SavingsGoalDialogState extends State<SavingsGoalDialog> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  String? _photoPath;
  String? _error;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _target = TextEditingController(
      text: widget.initial != null
          ? widget.initial!.target.round().toString()
          : '',
    );
    _photoPath = widget.initial?.photoPath;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final target = parseAmount(_target.text);
    if (name.isEmpty) {
      setState(() => _error = 'Give the goal a short name.');
      return;
    }
    if (name.length > 80) {
      setState(() => _error = 'Keep the name under 80 characters.');
      return;
    }
    if (target == null || target <= 0 || target > maxRelapseCost) {
      setState(() => _error = 'Enter a target amount above zero.');
      return;
    }
    Navigator.pop(
      context,
      GoalDialogResult(
        SavingsGoal(name: name, target: target, photoPath: _photoPath),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    setState(() => _picking = true);
    try {
      final path = await pickSavingsGoalPhoto();
      if (!mounted) return;
      if (path != null) setState(() => _photoPath = path);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not add that photo. Try another.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photoPath != null && File(_photoPath!).existsSync();
    return AppDialog(
      title: 'SAVINGS GOAL',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A name, a target, and an optional photo. The jar on Home and Progress fills as money is kept.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('goal-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Goal name'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('goal-target'),
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  prefixText: '${widget.currency.symbol}  ',
                  labelText: 'Target amount',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (hasPhoto) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_photoPath!),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  TextButton(
                    key: const ValueKey('goal-add-photo'),
                    onPressed: _picking ? null : _pickPhoto,
                    child: Text(hasPhoto ? 'CHANGE PHOTO' : 'ADD A PHOTO'),
                  ),
                  if (hasPhoto)
                    TextButton(
                      key: const ValueKey('goal-remove-photo'),
                      onPressed: () => setState(() => _photoPath = null),
                      child: const Text('REMOVE'),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: red, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('goal-save'),
                  onPressed: _save,
                  child: const Text('SAVE GOAL'),
                ),
              ),
              if (widget.initial != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    key: const ValueKey('goal-clear'),
                    onPressed: () =>
                        Navigator.pop(context, const GoalDialogResult(null)),
                    child: const Text('REMOVE GOAL'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSavingsGoalDialog(BuildContext context, WidgetRef ref) async {
  final recovery = ref.read(recoveryProvider);
  final result = await showDialog<GoalDialogResult>(
    context: context,
    builder: (_) => SavingsGoalDialog(
      initial: recovery.savingsGoal,
      currency: recovery.currency,
    ),
  );
  if (result == null || !context.mounted) return;
  if (!await saveAction(
    context,
    () => ref.read(recoveryProvider).updateSavingsGoal(result.goal),
  )) {
    return;
  }
  if (context.mounted) {
    AppNotice.show(
      context,
      result.goal == null ? 'GOAL REMOVED.' : 'GOAL UPDATED.',
      type: AppNoticeType.success,
    );
  }
}
