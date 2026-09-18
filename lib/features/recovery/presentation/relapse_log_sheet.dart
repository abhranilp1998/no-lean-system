import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../application/recovery_controller.dart';
import '../application/recovery_provider.dart';
import '../domain/craving_entry.dart';
import '../domain/relapse_log_entry.dart';
import 'peak_hour_gate_dialog.dart';
import 'relapse_auth_dialog.dart';

Future<void> showRelapseLogSheet(
  BuildContext context, {
  String source = 'app',
}) async {
  final recovery = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(recoveryProvider);
  if (recovery.isPeakHourLockActive) {
    final gateResult = await showPeakHourGateDialog(context, recovery);
    if (!context.mounted || gateResult == null) return;
    if (gateResult == PeakHourGateResult.openSos) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const EmergencyScreen(),
          fullscreenDialog: true,
        ),
      );
      return;
    }
  }
  final result = await showModalBottomSheet<_RelapseSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.black,
    builder: (_) => RelapseLogSheet(source: source),
  );
  if (result == null || !context.mounted) return;
  AppNotice.show(
    context,
    '${result.count} ${result.count == 1 ? 'RELAPSE' : 'RELAPSES'} RECORDED // HISTORY PRESERVED.',
    type: AppNoticeType.success,
  );
  if (result.openSos && context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const EmergencyScreen(),
        fullscreenDialog: true,
      ),
    );
  }
}

class RelapseLogSheet extends ConsumerStatefulWidget {
  const RelapseLogSheet({this.source = 'app', super.key});

  final String source;

  @override
  ConsumerState<RelapseLogSheet> createState() => _RelapseLogSheetState();
}

class _RelapseLogSheetState extends ConsumerState<RelapseLogSheet> {
  final _formKey = GlobalKey<FormState>();
  final _operationId = const Uuid().v4();
  final _entries = <_RelapseDraft>[_RelapseDraft()];
  bool _saving = false;
  bool _openSosAfterSave = false;
  String? _error;

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(int index) async {
    final current = _entries[index].occurredAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date != null && mounted) {
      setState(() {
        _entries[index].occurredAt = DateTime(
          date.year,
          date.month,
          date.day,
          current.hour,
          current.minute,
        );
        _error = null;
      });
    }
  }

  Future<void> _pickTime(int index) async {
    final current = _entries[index].occurredAt;
    final time = await _showRelapseTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time != null && mounted) {
      setState(() {
        _entries[index].occurredAt = DateTime(
          current.year,
          current.month,
          current.day,
          time.hour,
          time.minute,
        );
        _error = null;
      });
    }
  }

  Future<bool> _confirmReset() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF13060A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: red, width: 2),
            ),
            icon: const Icon(Icons.warning_amber_rounded, color: red, size: 42),
            title: Text(
              'CONFIRM RELAPSE',
              textAlign: TextAlign.center,
              style: displayFont(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: red,
                letterSpacing: 1.2,
              ),
            ),
            content: const Text(
              'This will reset your clean counter. Your earlier progress and history will remain intact.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.45),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('GO BACK'),
              ),
              FilledButton.icon(
                key: const ValueKey('confirm-relapse-reset'),
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: red,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.lock_reset),
                label: const Text('CONFIRM RESET'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _error = 'Complete every required relapse field.');
      return;
    }
    if (_entries.any((entry) => entry.occurredAt.isAfter(DateTime.now()))) {
      setState(
        () => _error =
            'An event cannot be in the future. Check each date and time.',
      );
      return;
    }
    if (!await _confirmReset() || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    AppFeedback.warning();
    try {
      final recovery = ref.read(recoveryProvider);
      final entries = _entries.map((entry) => entry.toDomain()).toList();
      var result = await recovery.recordRelapse(
        entries: entries,
        operationId: _operationId,
        source: widget.source,
      );
      if (!mounted) return;
      if (result == ProtectedActionResult.authenticationRequired) {
        final pin = await showRelapsePinDialog(
          context,
          actionLabel: 'SAVE RELAPSE',
        );
        if (!mounted || pin == null) return;
        result = await recovery.recordRelapse(
          entries: entries,
          operationId: _operationId,
          source: widget.source,
          pin: pin,
          tryBiometrics: false,
        );
      }
      if (!mounted) return;
      if (result == ProtectedActionResult.completed) {
        Navigator.pop(
          context,
          _RelapseSheetResult(
            count: _entries.length,
            openSos: _openSosAfterSave,
          ),
        );
      } else {
        setState(
          () => _error = result == ProtectedActionResult.lockedOut
              ? result.failureMessage
              : 'Authentication failed. Your history has not been changed.',
        );
      }
    } on RecoverySaveException catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _error = error.message?.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save these relapses. Check the details and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addEntry() {
    setState(() {
      _entries.add(_RelapseDraft());
      _error = null;
    });
  }

  void _removeEntry(int index) {
    setState(() {
      _entries.removeAt(index).dispose();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: FractionallySizedBox(
        heightFactor: .94,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              12 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: ListView(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: red.withValues(alpha: .15),
                                shape: BoxShape.circle,
                                border: Border.all(color: red),
                              ),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: red,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'LOG RELAPSE',
                                style: displayFont(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: red,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Record what happened without hiding it. This resets clean time; it does not erase the work already done.',
                          style: TextStyle(height: 1.45),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Every entry needs a type, context, and whether SOS was attempted. Dates and times use this device.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        for (var index = 0; index < _entries.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _RelapseEntryCard(
                              index: index,
                              entry: _entries[index],
                              saving: _saving,
                              canRemove: _entries.length > 1,
                              onDate: () => _pickDate(index),
                              onTime: () => _pickTime(index),
                              onRemove: () => _removeEntry(index),
                              onChanged: () => setState(() => _error = null),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: _saving || _entries.length >= 50
                              ? null
                              : _addEntry,
                          icon: const Icon(Icons.add),
                          label: const Text('ADD ANOTHER EVENT'),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          activeColor: red,
                          value: _openSosAfterSave,
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _openSosAfterSave = value ?? false,
                                ),
                          title: const Text('OPEN SOS AFTER SAVE'),
                          subtitle: const Text(
                            'Move directly into the 60-second override.',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(
                      _error!,
                      key: const ValueKey('relapse-form-error'),
                      style: const TextStyle(color: red),
                    ),
                  ),
                FilledButton.icon(
                  key: const ValueKey('save-relapse-events'),
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: red,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: Text(
                    _saving
                        ? 'SAVING...'
                        : 'SAVE ${_entries.length} ${_entries.length == 1 ? 'EVENT' : 'EVENTS'}',
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<TimeOfDay?> _showRelapseTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  var hour = initialTime.hour;
  var minute = initialTime.minute;
  return showDialog<TimeOfDay>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        key: const ValueKey('relapse-time-picker'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: const Text('SET RELAPSE TIME'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                key: const ValueKey('relapse-hour'),
                initialValue: hour,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'HOUR (24H)'),
                items: [
                  for (var value = 0; value < 24; value++)
                    DropdownMenuItem(
                      value: value,
                      child: Text(value.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => hour = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const ValueKey('relapse-minute'),
                initialValue: minute,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'MINUTE'),
                items: [
                  for (var value = 0; value < 60; value++)
                    DropdownMenuItem(
                      value: value,
                      child: Text(value.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => minute = value);
                },
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  TimeOfDay(hour: hour, minute: minute),
                ),
                child: const Text('SET TIME'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCEL'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RelapseEntryCard extends StatelessWidget {
  const _RelapseEntryCard({
    required this.index,
    required this.entry,
    required this.saving,
    required this.canRemove,
    required this.onDate,
    required this.onTime,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _RelapseDraft entry;
  final bool saving;
  final bool canRemove;
  final VoidCallback onDate;
  final VoidCallback onTime;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      accent: red,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'RELAPSE ${index + 1}',
                  style: eyebrowStyle.copyWith(color: red),
                ),
              ),
              IconButton(
                tooltip: 'Remove relapse ${index + 1}',
                onPressed: saving || !canRemove ? null : onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                key: ValueKey('relapse-date-$index'),
                onPressed: saving ? null : onDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(DateFormat.yMMMd().format(entry.occurredAt)),
              ),
              OutlinedButton.icon(
                key: ValueKey('relapse-time-$index'),
                onPressed: saving ? null : onTime,
                icon: const Icon(Icons.schedule),
                label: Text(DateFormat.jm().format(entry.occurredAt)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<RelapseType>(
            key: ValueKey('relapse-type-$index'),
            initialValue: entry.type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'RELAPSE TYPE'),
            dropdownColor: panelRaised,
            items: [
              for (final type in RelapseType.values)
                DropdownMenuItem(value: type, child: Text(type.label)),
            ],
            onChanged: saving
                ? null
                : (value) {
                    if (value == null) return;
                    entry.type = value;
                    onChanged();
                  },
          ),
          const SizedBox(height: 12),
          Text(
            'CONTEXT SIGNALS // SELECT ANY',
            style: eyebrowStyle.copyWith(color: magenta),
          ),
          const SizedBox(height: 5),
          const Text(
            'Choose every signal that fits. These stay structured; use the field below for what actually happened.',
            style: TextStyle(color: muted, fontSize: 10, height: 1.35),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tag in recoveryTriggerOptions)
                FilterChip(
                  key: ValueKey('relapse-context-$index-$tag'),
                  label: Text(tag, style: const TextStyle(fontSize: 10)),
                  selected: entry.contextTags.contains(tag),
                  selectedColor: magenta.withValues(alpha: .25),
                  checkmarkColor: magenta,
                  side: BorderSide(
                    color: entry.contextTags.contains(tag)
                        ? magenta
                        : muted.withValues(alpha: .45),
                  ),
                  onSelected: saving
                      ? null
                      : (selected) {
                          if (selected) {
                            entry.contextTags.add(tag);
                          } else {
                            entry.contextTags.remove(tag);
                          }
                          onChanged();
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey('relapse-note-$index'),
            controller: entry.noteController,
            enabled: !saving,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'WHAT HAPPENED? *',
              hintText: 'Trigger, decision point, and context...',
              alignLabelWithHint: true,
            ),
            validator: (value) {
              if ((value?.trim().length ?? 0) <
                  RelapseLogEntry.minimumNoteLength) {
                return 'Use at least ${RelapseLogEntry.minimumNoteLength} characters.';
              }
              return null;
            },
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('relapse-quantity-$index'),
            controller: entry.quantityController,
            enabled: !saving,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'QUANTITY (OPTIONAL)',
              hintText: 'Example: half a cup',
            ),
          ),
          SwitchListTile(
            key: ValueKey('relapse-attempted-sos-$index'),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: red,
            value: entry.attemptedSos,
            onChanged: saving
                ? null
                : (value) {
                    entry.attemptedSos = value;
                    onChanged();
                  },
            title: const Text('SOS ATTEMPTED'),
            subtitle: const Text(
              'Mark whether you opened the override before this event.',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelapseDraft {
  DateTime occurredAt = DateTime.now();
  RelapseType type = RelapseType.fullLean;
  bool attemptedSos = false;
  final contextTags = <String>{};
  final noteController = TextEditingController();
  final quantityController = TextEditingController();

  RelapseLogEntry toDomain() => RelapseLogEntry(
    occurredAt: occurredAt,
    type: type,
    note: noteController.text,
    attemptedSos: attemptedSos,
    quantity: quantityController.text,
    contextTags: contextTags.toList(growable: false),
  );

  void dispose() {
    noteController.dispose();
    quantityController.dispose();
  }
}

class _RelapseSheetResult {
  const _RelapseSheetResult({required this.count, required this.openSos});

  final int count;
  final bool openSos;
}
