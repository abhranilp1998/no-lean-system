import '../domain/slip_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/glass_card.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../application/recovery_controller.dart';
import '../application/recovery_provider.dart';
import '../domain/craving_entry.dart';
import '../domain/dose_safety.dart';
import '../domain/dose_units.dart';
import '../domain/relapse_log_entry.dart';
import '../domain/mixing_safety_net.dart';
import '../domain/multi_day_log.dart';
import '../domain/recovery_event.dart';
import 'multi_day_picker.dart';
import 'dose_safety_cards.dart';
import 'peak_hour_gate_dialog.dart';
import 'relapse_auth_dialog.dart';
import '../../cravings/presentation/craving_dialog.dart';

/// Rounds "about [hours] h ago" to the minute; never in the future.
DateTime relapseHoursAgo(int hours, {DateTime? now}) {
  final at = (now ?? DateTime.now()).subtract(Duration(hours: hours));
  return DateTime(at.year, at.month, at.day, at.hour, at.minute);
}

const relapseAgoChoices = [1, 2, 3, 6, 12];

/// P0-5 one-tap "Used": records a relapse at now, no form. Double-taps are
/// absorbed by the controller. If the history lock needs a PIN, or the
/// write fails, falls back to the full logger.
Future<void> quickLogUsed(
  BuildContext context, {
  String source = 'one_tap',
}) async {
  final recovery = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(recoveryProvider);
  ProtectedActionResult result;
  try {
    result = await recovery.quickLogUsed(source: source);
  } catch (_) {
    result = ProtectedActionResult.denied;
  }
  if (!context.mounted) return;
  if (result != ProtectedActionResult.completed) {
    await showRelapseLogSheet(context, source: source);
    return;
  }
  AppNotice.show(
    context,
    slipLoggedMessage(seed: DateTime.now().minute),
    type: AppNoticeType.success,
    actionLabel: 'ADD DETAILS',
    onAction: () => showRelapseLogSheet(context, source: source),
  );
}

Future<void> showRelapseLogSheet(
  BuildContext context, {
  String source = 'app',
  DateTime? initialOccurredAt,
  String? initialNote,
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
    builder: (_) => RelapseLogSheet(
      source: source,
      initialOccurredAt: initialOccurredAt,
      initialNote: initialNote,
    ),
  );
  if (result == null || !context.mounted) return;
  AppNotice.show(
    context,
    result.multiDay
        ? multiDayRecordedMessage(result.count, days: result.dayCount)
        : slipsRecordedMessage(result.count),
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
  // (B): any mixed save, from any entry point (dashboard, Tell, check-ins),
  // gets the safety net right away.
  if (result.mixed && context.mounted) await showMixingSafetyNetSheet(context);
}

/// Opens one saved relapse for correction: its facts and its date/time.
/// Only that entry changes; other days from the same save are untouched.
Future<void> showRelapseEditSheet(
  BuildContext context,
  RecoveryEvent event,
) async {
  final result = await showModalBottomSheet<_RelapseSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.black,
    builder: (_) => RelapseLogSheet(editing: event),
  );
  if (result == null || !context.mounted) return;
  AppNotice.show(context, entryUpdatedMessage, type: AppNoticeType.success);
  if (result.mixed && context.mounted) await showMixingSafetyNetSheet(context);
}

class RelapseLogSheet extends ConsumerStatefulWidget {
  const RelapseLogSheet({
    this.source = 'app',
    this.initialOccurredAt,
    this.editing,
    this.now,
    this.initialNote,
    super.key,
  });

  /// Prefills the first entry's note (e.g. after a danger-zone visit).
  final String? initialNote;

  final String source;

  /// A saved relapse to correct. When set, the sheet edits that one entry
  /// instead of logging new ones.
  final RecoveryEvent? editing;

  /// Fixed clock for the multi-day picker in tests and screenshots.
  final DateTime? now;

  /// Prefills the first entry's time (a backfill "about X h ago").
  final DateTime? initialOccurredAt;

  @override
  ConsumerState<RelapseLogSheet> createState() => _RelapseLogSheetState();
}

class _RelapseLogSheetState extends ConsumerState<RelapseLogSheet> {
  final _formKey = GlobalKey<FormState>();
  final _operationId = const Uuid().v4();
  final _entries = <_RelapseDraft>[_RelapseDraft()];

  /// Picked days for a multi-day log; null for the normal one-by-one form.
  List<MultiDaySlot>? _days;
  bool _saving = false;
  bool _openSosAfterSave = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing != null) {
      _entries.first.fillFrom(editing);
      return;
    }
    final at = widget.initialOccurredAt;
    if (at != null && !at.isAfter(DateTime.now())) {
      _entries.first.occurredAt = at;
    }
    final note = widget.initialNote;
    if (note != null) _entries.first.noteController.text = note;
  }

  void _setAgo(int index, int hours) => setState(() {
    _entries[index].occurredAt = relapseHoursAgo(hours);
    _error = null;
  });

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  bool get _editing => widget.editing != null;
  DateTime _clock() => widget.now ?? DateTime.now();

  /// Doses per day when every picked day has the same number, else null.
  int? _uniformDoseCount(List<MultiDaySlot>? slots) {
    if (slots == null || slots.isEmpty) return null;
    final counts = {
      for (final d in slotDays(slots)) dosesOnDay(slots, d).length,
    };
    return counts.length == 1 ? counts.first : null;
  }

  int _maxDoseCount(List<MultiDaySlot> slots) => slots.isEmpty
      ? 1
      : [
          for (final d in slotDays(slots)) dosesOnDay(slots, d).length,
        ].reduce((a, b) => a > b ? a : b);

  Future<void> _openMultiDayPicker() async {
    final current = _days;
    final pick = await showMultiDayPicker(
      context,
      initialDays: current == null ? const [] : slotDays(current),
      initialHour: current?.firstOrNull?.hour ?? multiDayDefaultHour,
      initialMinute: current?.firstOrNull?.minute ?? multiDayDefaultMinute,
      now: widget.now,
    );
    if (pick == null || !mounted) return;
    final now = _clock();
    final uniform = _uniformDoseCount(current) ?? 1;
    setState(() {
      // Days that stay picked keep every dose the user already set up; new
      // days start with the same number of doses as the others.
      final next = <MultiDaySlot>[];
      for (final slot in pick.slots(now)) {
        final kept = current == null
            ? <MultiDaySlot>[]
            : dosesOnDay(current, slot.day);
        if (kept.isNotEmpty) {
          next.addAll(kept.map((dose) => clampSlotToNow(dose, now)));
        } else if (uniform <= 1) {
          next.add(slot);
        } else {
          next.addAll(defaultDosesForDay(slot.day, uniform, now: now));
        }
      }
      _days = sortedSlots(next);
      for (final extra in _entries.skip(1)) {
        extra.dispose();
      }
      _entries.removeRange(1, _entries.length);
      final note = _entries.first.noteController;
      if (note.text.trim().isEmpty) {
        note.text = 'Logging this later for days I missed.';
      }
      _error = null;
    });
  }

  void _leaveMultiDay() => setState(() {
    _days = null;
    _error = null;
  });

  /// Removes one dose. A day left with no doses disappears; with no days
  /// left the form goes back to a single event.
  void _removeDose(int index) => setState(() {
    final days = List<MultiDaySlot>.of(_days!)..removeAt(index);
    _days = days.isEmpty ? null : days;
    _error = null;
  });

  void _addDose(DateTime day) {
    final slot = nextDoseSlot(_days!, day, now: _clock());
    setState(() {
      if (slot == null) {
        _error = _days!.length >= multiDayMaxDays
            ? 'You can log at most $multiDayMaxDays entries at once.'
            : 'No free time left on that day for another dose.';
        return;
      }
      if (_days!.length >= multiDayMaxDays) {
        _error = 'You can log at most $multiDayMaxDays entries at once.';
        return;
      }
      _days = sortedSlots([..._days!, slot]);
      _error = null;
    });
  }

  /// Applies [count] doses to every picked day with evenly spread default
  /// times. Per-dose overrides are kept by position.
  void _setDosesPerDay(int count) {
    final days = _days;
    if (days == null) return;
    final n = count.clamp(1, multiDayMaxDosesPerDay);
    final dayList = slotDays(days);
    if (dayList.length * n > multiDayMaxDays) return;
    final now = _clock();
    setState(() {
      _days = sortedSlots([
        for (final day in dayList)
          ...defaultDosesForDay(day, n, now: now, carry: dosesOnDay(days, day)),
      ]);
      _error = null;
    });
  }

  Future<void> _editDose(int index) async {
    final slots = _days!;
    final slot = slots[index];
    final outcome = await showDialog<_DoseEditResult>(
      context: context,
      builder: (_) => _DoseDialog(slot: slot),
    );
    if (outcome == null || !mounted) return;
    if (outcome.remove) {
      _removeDose(index);
      return;
    }
    final updated = slot
        .withTime(outcome.hour, outcome.minute)
        .withOverride(type: outcome.type);
    String? problem;
    DoseAmount? dose;
    final amountText = outcome.amountText.trim();
    if (amountText.isNotEmpty) {
      final bottleMl = ref.read(recoveryProvider).bottleMl;
      final amount = parseAmount(amountText);
      if (amount == null) {
        problem = 'Enter the amount as a number, or leave it blank.';
      } else {
        var unit = outcome.unit;
        final check = doseSanityCheck(amount, unit, bottleMl: bottleMl);
        if (check != null) {
          var keepable = true;
          try {
            DoseAmount.entered(amount, unit, bottleMl: bottleMl);
          } on ArgumentError {
            keepable = false;
          }
          final choice = await _confirmDoseUnit(
            check,
            unit,
            keepable: keepable,
          );
          if (!mounted || choice == null) return;
          unit = choice;
        }
        try {
          dose = DoseAmount.entered(amount, unit, bottleMl: bottleMl);
        } on ArgumentError catch (error) {
          problem = error.message?.toString();
        }
      }
    }
    if (!mounted) return;
    final withDose = updated.withOverride(type: outcome.type, dose: dose);
    setState(() {
      if (problem != null) {
        _error = problem;
      } else if (withDose.occurredAt.isAfter(_clock())) {
        _error = 'That time has not happened yet today. Pick an earlier time.';
      } else if (timeTakenOnDay(
        slots,
        slot.day,
        outcome.hour,
        outcome.minute,
        ignoreIndex: index,
      )) {
        _error =
            'Another dose on ${DateFormat.MMMd().format(slot.day)} is already at ${DateFormat.jm().format(withDose.occurredAt)}. Pick a different time.';
      } else {
        _days = sortedSlots(List.of(slots)..[index] = withDose);
        _error = null;
      }
    });
  }

  Future<bool> _confirmMultiDay(
    List<RelapseLogEntry> entries,
    RelapseLogEntry sharedEntry,
  ) async {
    final resets = entriesResetLeanTimer(entries);
    final sample = sharedEntry;
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: panel,
          builder: (sheetContext) => _MultiDayConfirmSheet(
            entries: entries,
            sample: sample,
            resetsLeanTimer: resets,
          ),
        ) ??
        false;
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
    final time = await showRelapseTimePicker(
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

  Future<bool> _confirmReset({bool resetsLeanTimer = true}) async {
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
            content: Text(
              resetsLeanTimer
                  ? 'This will reset your clean counter. Your earlier progress and history will remain intact.'
                  : 'Benzo-only use is saved for your safety log. It does not reset your lean clean time.',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.45),
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
                icon: Icon(resetsLeanTimer ? Icons.lock_reset : Icons.save),
                label: Text(resetsLeanTimer ? 'CONFIRM RESET' : 'SAVE IT'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// "Did you mean 250 ml?" Returns the unit to use, or null to go back
  /// and edit.
  Future<DoseUnit?> _confirmDoseUnit(
    DoseSanityCheck check,
    DoseUnit current, {
    required bool keepable,
  }) => showDialog<DoseUnit>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        key: const ValueKey('dose-sanity-dialog'),
        backgroundColor: panelRaised,
        title: const Text('CHECK THE UNIT'),
        content: Text(check.message, style: const TextStyle(height: 1.45)),
        actions: [
          TextButton(
            key: const ValueKey('dose-sanity-edit'),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('EDIT'),
          ),
          if (keepable)
            TextButton(
              key: const ValueKey('dose-sanity-keep'),
              onPressed: () => Navigator.pop(dialogContext, current),
              child: Text('KEEP ${current.label.toUpperCase()}'),
            ),
          if (check.suggestedUnit != null)
            FilledButton(
              key: const ValueKey('dose-sanity-switch'),
              onPressed: () =>
                  Navigator.pop(dialogContext, check.suggestedUnit),
              child: Text('USE ${check.suggestedUnit!.label.toUpperCase()}'),
            ),
        ],
      );
    },
  );

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _error = 'Complete every required relapse field.');
      return;
    }
    final days = _days;
    if (days != null
        ? days.any((slot) => slot.occurredAt.isAfter(DateTime.now()))
        : _entries.any((entry) => entry.occurredAt.isAfter(DateTime.now()))) {
      setState(
        () => _error =
            'An event cannot be in the future. Check each date and time.',
      );
      return;
    }
    final bottleMl = ref.read(recoveryProvider).bottleMl;
    for (final entry in _entries) {
      final amount = parseAmount(entry.amountController.text);
      if (amount == null) continue;
      final check = doseSanityCheck(amount, entry.unit, bottleMl: bottleMl);
      if (check == null) continue;
      bool keepable;
      try {
        DoseAmount.entered(amount, entry.unit, bottleMl: bottleMl);
        keepable = true;
      } on ArgumentError {
        keepable = false;
      }
      final choice = await _confirmDoseUnit(
        check,
        entry.unit,
        keepable: keepable,
      );
      if (!mounted || choice == null) return;
      if (choice != entry.unit) setState(() => entry.unit = choice);
    }
    final recovery = ref.read(recoveryProvider);
    if (days != null) {
      if (days.length > multiDayMaxDays) {
        setState(
          () =>
              _error = 'You can log at most $multiDayMaxDays entries at once.',
        );
        return;
      }
      final dup = firstDuplicateSlot(days);
      if (dup != null) {
        setState(
          () => _error =
              'Two doses on ${DateFormat.MMMd().format(dup.day)} are both at ${DateFormat.jm().format(dup.occurredAt)}. Change one of them.',
        );
        return;
      }
    }
    final List<RelapseLogEntry> entries;
    late final RelapseLogEntry shared;
    try {
      final drafts = _entries
          .map((entry) => entry.toDomain(bottleMl: recovery.bottleMl))
          .toList();
      shared = drafts.first;
      entries = days != null
          ? expandMultiDayEntries(drafts.first, sortedSlots(days))
          : drafts;
      for (final entry in entries) {
        entry.validate();
      }
    } on ArgumentError catch (error) {
      setState(() => _error = error.message?.toString());
      return;
    }
    final confirmed = _editing
        ? true
        : days != null
        ? await _confirmMultiDay(entries, shared)
        : await _confirmReset(resetsLeanTimer: entriesResetLeanTimer(entries));
    if (!confirmed || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    AppFeedback.warning();
    try {
      Future<ProtectedActionResult> write({String? pin}) {
        final editing = widget.editing;
        if (editing != null) {
          return recovery.editRelapseEntry(
            id: editing.id,
            entry: entries.single,
            pin: pin,
            tryBiometrics: pin == null,
          );
        }
        return recovery.recordRelapse(
          entries: entries,
          operationId: _operationId,
          source: widget.source,
          extraMetadata: days != null
              ? const {multiDayMetadataKey: true}
              : const {},
          pin: pin,
          tryBiometrics: pin == null,
        );
      }

      var result = await write();
      if (!mounted) return;
      if (result == ProtectedActionResult.authenticationRequired) {
        final pin = await showRelapsePinDialog(
          context,
          actionLabel: _editing ? 'AUTHORIZE EDIT' : 'SAVE RELAPSE',
        );
        if (!mounted || pin == null) return;
        result = await write(pin: pin);
      }
      if (!mounted) return;
      if (result == ProtectedActionResult.completed) {
        Navigator.pop(
          context,
          _RelapseSheetResult(
            count: entries.length,
            openSos: _openSosAfterSave,
            mixed: isMixedSave(entries.map((e) => e.type)),
            multiDay: days != null,
            dayCount: days == null ? 0 : slotDays(days).length,
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
    final recovery = ref.watch(recoveryProvider);
    final days = _days;
    final warnings = loggingSafetyWarnings(
      draft: days != null
          ? [
              for (final d in days)
                (type: d.type ?? _entries.first.type, at: d.occurredAt),
            ]
          : [for (final e in _entries) (type: e.type, at: e.occurredAt)],
      events: recovery.events,
      cleanStreakDays: recovery.streak,
      now: DateTime.now(),
    );
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
                                _editing
                                    ? 'EDIT ENTRY'
                                    : days != null
                                    ? 'LOG SEVERAL DAYS'
                                    : 'LOG RELAPSE',
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
                        Text(
                          _editing
                              ? 'Correct this one entry. Other days saved alongside it stay as they are.'
                              : days != null
                              ? 'Describe these days once. Every dose is saved as its own entry, so you can fix any single one later from History.'
                              : 'Record what happened without hiding it. This resets clean time; it does not erase the work already done.',
                          style: const TextStyle(height: 1.45),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Every entry needs a type, context, and whether SOS was attempted. Dates and times use this device.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        if (!_editing && days == null) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            key: const ValueKey('open-multi-day-picker'),
                            onPressed: _saving ? null : _openMultiDayPicker,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cyan,
                              side: BorderSide(
                                color: cyan.withValues(alpha: .6),
                              ),
                            ),
                            icon: const Icon(Icons.date_range),
                            label: const Text('MISSED A FEW DAYS? LOG SEVERAL'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (days != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MultiDayCard(
                              days: days,
                              saving: _saving,
                              dosesPerDay:
                                  _uniformDoseCount(days) ??
                                  _maxDoseCount(days),
                              mixedCounts: _uniformDoseCount(days) == null,
                              onChangeDays: _openMultiDayPicker,
                              onEditDose: _editDose,
                              onRemoveDose: _removeDose,
                              onAddDose: _addDose,
                              onDosesPerDay: _setDosesPerDay,
                              onLeave: _leaveMultiDay,
                            ),
                          ),
                        for (var index = 0; index < _entries.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _RelapseEntryCard(
                              index: index,
                              entry: _entries[index],
                              bottleMl: recovery.bottleMl,
                              saving: _saving,
                              title: _editing
                                  ? 'ENTRY'
                                  : days != null
                                  ? 'SAME FOR ALL ${slotDays(days).length} DAYS'
                                  : null,
                              showWhen: days == null,
                              canRemove: _entries.length > 1,
                              onDate: () => _pickDate(index),
                              onTime: () => _pickTime(index),
                              onAgo: (hours) => _setAgo(index, hours),
                              onRemove: () => _removeEntry(index),
                              onChanged: () => setState(() => _error = null),
                            ),
                          ),
                        if (warnings.isNotEmpty) ...[
                          for (final warning in warnings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: DoseWarningCard(warning: warning),
                            ),
                          const OverdoseSignsCard(),
                          const SizedBox(height: 8),
                        ],
                        if (!_editing && days == null)
                          TextButton.icon(
                            onPressed: _saving || _entries.length >= 50
                                ? null
                                : _addEntry,
                            icon: const Icon(Icons.add),
                            label: const Text('ADD ANOTHER EVENT'),
                          ),
                        if (!_editing)
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
                        : _editing
                        ? 'SAVE CHANGES'
                        : days != null
                        ? 'LOG ${days.length} ${days.length == 1 ? 'ENTRY' : 'ENTRIES'}'
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

/// Hour/minute picker used for relapse times (24 h dropdowns, which stay
/// readable at large text sizes).
Future<TimeOfDay?> showRelapseTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String title = 'SET RELAPSE TIME',
}) {
  var hour = initialTime.hour;
  var minute = initialTime.minute;
  return showDialog<TimeOfDay>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        key: const ValueKey('relapse-time-picker'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(title),
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
    required this.bottleMl,
    required this.saving,
    required this.canRemove,
    this.title,
    this.showWhen = true,
    required this.onDate,
    required this.onTime,
    required this.onAgo,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _RelapseDraft entry;
  final double bottleMl;
  final bool saving;
  final bool canRemove;

  /// Card heading; defaults to "RELAPSE n".
  final String? title;

  /// False in multi-day mode, where each day's date and time live in the
  /// day list instead.
  final bool showWhen;
  final VoidCallback onDate;
  final VoidCallback onTime;
  final ValueChanged<int> onAgo;
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
                  title ?? 'RELAPSE ${index + 1}',
                  style: eyebrowStyle.copyWith(color: red),
                ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: 'Remove relapse ${index + 1}',
                  onPressed: saving ? null : onRemove,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (showWhen) ...[
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
            Wrap(
              spacing: 6,
              children: [
                Text('ABOUT', style: microStyle),
                for (final hours in relapseAgoChoices)
                  ActionChip(
                    key: ValueKey('relapse-ago-$index-$hours'),
                    label: Text('${hours}H AGO'),
                    onPressed: saving ? null : () => onAgo(hours),
                  ),
              ],
            ),
          ],
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
          _DoseFields(
            index: index,
            entry: entry,
            bottleMl: bottleMl,
            saving: saving,
            onChanged: onChanged,
          ),
          TextFormField(
            key: ValueKey('relapse-quantity-$index'),
            controller: entry.quantityController,
            enabled: !saving,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'QUANTITY NOTE (OPTIONAL)',
              hintText: 'Example: half a cup',
              helperText:
                  'Exact text like "250ml" or "2 bottles" also counts as the amount.',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey('relapse-cost-$index'),
            controller: entry.costController,
            enabled: !saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'WHAT IT COST (OPTIONAL)',
              prefixText: '₹ ',
              hintText: 'Example: 450',
              helperText: 'Real cost replaces the daily-spend estimate.',
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return null;
              final cost = parseMoney(text);
              if (cost == null) return 'Enter an amount like 450 or 1,200.';
              if (cost > maxRelapseCost) return 'That amount is too large.';
              return null;
            },
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 12),
          StressPicker(
            keyPrefix: 'relapse-stress-$index',
            value: entry.stress,
            enabled: !saving,
            onChanged: (value) {
              entry.stress = value;
              onChanged();
            },
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
  DoseUnit unit = DoseUnit.bottle;
  int? stress;
  final contextTags = <String>{};
  final noteController = TextEditingController();
  final quantityController = TextEditingController();
  final amountController = TextEditingController();
  final costController = TextEditingController();

  /// Prefills this draft from a saved relapse for editing.
  void fillFrom(RecoveryEvent event) {
    final m = event.metadata;
    occurredAt = event.timestamp;
    // Edit the type the user picked, not the brand-corrected one.
    type =
        RelapseTypeLabel.fromName(m['relapseTypeFrom']) ??
        RelapseTypeLabel.fromName(m['relapseType']) ??
        RelapseType.fullLean;
    attemptedSos = m['attemptedSos'] == true;
    final s = m['stress'];
    stress = s is num ? s.round() : null;
    contextTags
      ..clear()
      ..addAll(switch (m['contextTags']) {
        final List values => values.whereType<String>(),
        _ => const <String>[],
      });
    noteController.text = (m['note'] as String?) ?? '';
    quantityController.text = (m['quantity'] as String?) ?? '';
    final dose = DoseAmount.fromMetadata(m);
    if (dose != null && m['amountSource'] != 'parsed') {
      unit = dose.unit;
      amountController.text = formatAmount(dose.amount);
    }
    final cost = m['cost'];
    if (cost is num) {
      costController.text = cost == cost.roundToDouble()
          ? cost.toInt().toString()
          : cost.toString();
    }
  }

  /// The amount field wins; otherwise an exact free-text quantity is used.
  RelapseLogEntry toDomain({required double bottleMl}) {
    final amount = parseAmount(amountController.text);
    final typed = amount == null
        ? null
        : DoseAmount.entered(amount, unit, bottleMl: bottleMl);
    final parsed = typed == null
        ? parseQuantityText(quantityController.text, bottleMl: bottleMl)
        : null;
    final costText = costController.text.trim();
    return RelapseLogEntry(
      occurredAt: occurredAt,
      type: type,
      note: noteController.text,
      attemptedSos: attemptedSos,
      quantity: quantityController.text,
      contextTags: contextTags.toList(growable: false),
      dose: typed ?? parsed,
      doseParsedFromText: parsed != null,
      stress: stress,
      cost: costText.isEmpty ? null : parseMoney(costText),
    );
  }

  void dispose() {
    noteController.dispose();
    quantityController.dispose();
    amountController.dispose();
    costController.dispose();
  }
}

/// Amount + unit, with the live ml conversion so the user sees exactly
/// what will be stored.
class _DoseFields extends StatelessWidget {
  const _DoseFields({
    required this.index,
    required this.entry,
    required this.bottleMl,
    required this.saving,
    required this.onChanged,
  });

  final int index;
  final _RelapseDraft entry;
  final double bottleMl;
  final bool saving;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final amount = parseAmount(entry.amountController.text);
    String? preview;
    if (amount != null) {
      final ml = toMl(amount, entry.unit, bottleMl: bottleMl);
      preview = ml == null
          ? '${formatAmount(amount)} ${entry.unit.labelFor(amount)} // counted separately from ml'
          : entry.unit == DoseUnit.bottle
          ? '= ${formatMl(ml)} at ${formatMl(bottleMl)} per bottle'
          : '= ${formatMl(ml)}';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: ValueKey('relapse-amount-$index'),
          controller: entry.amountController,
          enabled: !saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'AMOUNT (OPTIONAL)',
            hintText: 'Example: 2.5, 2,5 or 1/2',
            helperText: preview,
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return null;
            final parsed = parseAmount(text);
            if (parsed == null) {
              return 'Enter a number above 0, like 2.5, 2,5, 1/2 or half.';
            }
            // Implausible sizes are caught by the unit check on save, which
            // can offer the likely unit ("Did you mean 250 ml?").
            return null;
          },
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final unit in DoseUnit.values)
              ChoiceChip(
                key: ValueKey('relapse-unit-$index-${unit.name}'),
                label: Text(unit.label, style: const TextStyle(fontSize: 11)),
                selected: entry.unit == unit,
                selectedColor: red.withValues(alpha: .25),
                onSelected: saving
                    ? null
                    : (_) {
                        entry.unit = unit;
                        onChanged();
                      },
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RelapseSheetResult {
  const _RelapseSheetResult({
    required this.count,
    required this.openSos,
    this.mixed = false,
    this.multiDay = false,
    this.dayCount = 0,
  });

  final int dayCount;
  final int count;
  final bool openSos;
  final bool mixed;
  final bool multiDay;
}

/// The picked days, each with its list of doses. Tap a dose to change its
/// time, type or amount; "+ DOSE" adds another one on that day.
class _MultiDayCard extends StatelessWidget {
  const _MultiDayCard({
    required this.days,
    required this.saving,
    required this.dosesPerDay,
    required this.mixedCounts,
    required this.onChangeDays,
    required this.onEditDose,
    required this.onRemoveDose,
    required this.onAddDose,
    required this.onDosesPerDay,
    required this.onLeave,
  });

  final List<MultiDaySlot> days;
  final bool saving;
  final int dosesPerDay;
  final bool mixedCounts;
  final VoidCallback onChangeDays;
  final ValueChanged<int> onEditDose;
  final ValueChanged<int> onRemoveDose;
  final ValueChanged<DateTime> onAddDose;
  final ValueChanged<int> onDosesPerDay;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final dayList = slotDays(days);
    final canMore =
        dosesPerDay < multiDayMaxDosesPerDay &&
        dayList.length * (dosesPerDay + 1) <= multiDayMaxDays;
    return GlassCard(
      key: const ValueKey('multi-day-card'),
      accent: cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${dayList.length} ${dayList.length == 1 ? 'DAY' : 'DAYS'} PICKED',
            style: eyebrowStyle.copyWith(color: cyan),
          ),
          const SizedBox(height: 4),
          Text(
            multiDayEntrySummary(days),
            key: const ValueKey('multi-day-summary'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a dose to change its time, type or amount. Add as many doses as that day had. Each one is saved separately.',
            style: TextStyle(color: muted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'DOSES PER DAY (ALL DAYS)',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
              IconButton(
                key: const ValueKey('multi-day-doses-minus'),
                tooltip: 'Fewer doses per day',
                onPressed: saving || dosesPerDay <= 1
                    ? null
                    : () => onDosesPerDay(dosesPerDay - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                mixedCounts ? 'MIXED' : '$dosesPerDay',
                key: const ValueKey('multi-day-doses-count'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              IconButton(
                key: const ValueKey('multi-day-doses-plus'),
                tooltip: 'More doses per day',
                onPressed: saving || !canMore
                    ? null
                    : () => onDosesPerDay(dosesPerDay + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const Divider(height: 14),
          for (final day in dayList) ...[
            _dayRow(day),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('multi-day-change'),
                onPressed: saving ? null : onChangeDays,
                icon: const Icon(Icons.date_range),
                label: const Text('CHANGE DAYS'),
              ),
              TextButton(
                key: const ValueKey('multi-day-leave'),
                onPressed: saving ? null : onLeave,
                child: const Text('LOG ONE EVENT INSTEAD'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayRow(DateTime day) {
    final key = DateFormat('yyyy-MM-dd').format(day);
    final indexes = [
      for (var i = 0; i < days.length; i++)
        if (days[i].day == day) i,
    ];
    return Column(
      key: ValueKey('multi-day-row-$key'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEE d MMM').format(day).toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var n = 0; n < indexes.length; n++)
              InputChip(
                key: ValueKey(
                  n == 0 ? 'multi-day-slot-$key' : 'multi-day-slot-$key-$n',
                ),
                label: Text(
                  doseChipLabel(days[indexes[n]]),
                  style: const TextStyle(fontSize: 11),
                ),
                onPressed: saving ? null : () => onEditDose(indexes[n]),
                onDeleted: saving ? null : () => onRemoveDose(indexes[n]),
                deleteButtonTooltipMessage: indexes.length == 1
                    ? 'Remove this day'
                    : 'Remove this dose',
              ),
            ActionChip(
              key: ValueKey('multi-day-add-dose-$key'),
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('DOSE', style: TextStyle(fontSize: 11)),
              onPressed: saving ? null : () => onAddDose(day),
            ),
          ],
        ),
      ],
    );
  }
}

/// "9:00 PM", or "9:00 PM · 250 ml · BENZO" when the dose has its own
/// amount or type.
String doseChipLabel(MultiDaySlot slot) => [
  DateFormat.jm().format(slot.occurredAt),
  if (slot.dose != null) slot.dose!.display,
  if (slot.type != null) slot.type!.label,
].join(' · ');

class _DoseEditResult {
  const _DoseEditResult({
    this.remove = false,
    this.hour = 0,
    this.minute = 0,
    this.type,
    this.amountText = '',
    this.unit = DoseUnit.bottle,
  });

  final bool remove;
  final int hour;
  final int minute;
  final RelapseType? type;
  final String amountText;
  final DoseUnit unit;
}

/// Edits one dose: its time, and optionally its own type and amount. Blank
/// means "same as the shared entry".
class _DoseDialog extends StatefulWidget {
  const _DoseDialog({required this.slot});

  final MultiDaySlot slot;

  @override
  State<_DoseDialog> createState() => _DoseDialogState();
}

class _DoseDialogState extends State<_DoseDialog> {
  late int _hour = widget.slot.hour;
  late int _minute = widget.slot.minute;
  late RelapseType? _type = widget.slot.type;
  late DoseUnit _unit = widget.slot.dose?.unit ?? DoseUnit.bottle;
  late final TextEditingController _amount = TextEditingController(
    text: widget.slot.dose == null
        ? ''
        : formatAmount(widget.slot.dose!.amount),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final time = await showRelapseTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
      title:
          'TIME ON ${DateFormat.MMMd().format(widget.slot.day).toUpperCase()}',
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
    final time = DateFormat.jm().format(DateTime(2000, 1, 1, _hour, _minute));
    return AlertDialog(
      key: const ValueKey('dose-dialog'),
      backgroundColor: panelRaised,
      title: Text(
        'DOSE ON ${DateFormat.MMMd().format(widget.slot.day).toUpperCase()}',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('dose-time'),
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(time),
            ),
            const SizedBox(height: 14),
            const Text(
              'Only change these if this dose was different from the shared details.',
              style: TextStyle(color: muted, fontSize: 11, height: 1.35),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<RelapseType?>(
              key: const ValueKey('dose-type'),
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'TYPE'),
              dropdownColor: panelRaised,
              items: [
                const DropdownMenuItem<RelapseType?>(
                  value: null,
                  child: Text('SAME AS SHARED'),
                ),
                for (final type in RelapseType.values)
                  DropdownMenuItem<RelapseType?>(
                    value: type,
                    child: Text(type.label),
                  ),
              ],
              onChanged: (value) => setState(() => _type = value),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('dose-amount'),
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'AMOUNT',
                      hintText: 'Same as shared',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<DoseUnit>(
                  key: const ValueKey('dose-unit'),
                  value: _unit,
                  dropdownColor: panelRaised,
                  items: [
                    for (final unit in DoseUnit.values)
                      DropdownMenuItem(value: unit, child: Text(unit.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _unit = value);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('dose-remove'),
          onPressed: () =>
              Navigator.pop(context, const _DoseEditResult(remove: true)),
          child: const Text('REMOVE DOSE'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          key: const ValueKey('dose-done'),
          onPressed: () => Navigator.pop(
            context,
            _DoseEditResult(
              hour: _hour,
              minute: _minute,
              type: _type,
              amountText: _amount.text,
              unit: _unit,
            ),
          ),
          child: const Text('DONE'),
        ),
      ],
    );
  }
}

/// "Log N entries" summary shown before a multi-day save, grouped by day.
class _MultiDayConfirmSheet extends StatelessWidget {
  const _MultiDayConfirmSheet({
    required this.entries,
    required this.sample,
    required this.resetsLeanTimer,
  });

  final List<RelapseLogEntry> entries;
  final RelapseLogEntry sample;
  final bool resetsLeanTimer;

  /// " · 250 ml · BENZO" for a dose that differs from the shared entry.
  String _overrideNote(RelapseLogEntry e) {
    final parts = [
      if (e.dose != null && e.dose?.display != sample.dose?.display)
        e.dose!.display,
      if (e.effectiveType != sample.effectiveType) e.effectiveType.label,
    ];
    return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final n = entries.length;
    final label = 'LOG $n ${n == 1 ? 'ENTRY' : 'ENTRIES'}';
    final byDay = <DateTime, List<RelapseLogEntry>>{};
    for (final e in entries) {
      byDay.putIfAbsent(dayOnly(e.occurredAt), () => []).add(e);
    }
    final dayKeys = byDay.keys.toList()..sort();
    final summary = multiDayEntrySummaryCounts(n, dayKeys.length);
    final facts = <String>[
      sample.effectiveType.label,
      if (sample.dose != null) sample.dose!.display,
      if (sample.cost != null) money(sample.cost!),
      if (sample.stress != null) 'Stress ${sample.stress}/5',
      ...sample.normalizedContextTags,
    ];
    return Padding(
      key: const ValueKey('multi-day-confirm'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CHECK BEFORE SAVING',
            style: displayFont(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: cyan,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$summary, each saved on its own:',
            style: const TextStyle(height: 1.4),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final day in dayKeys)
                  Padding(
                    key: ValueKey(
                      'multi-day-confirm-day-${DateFormat('yyyy-MM-dd').format(day)}',
                    ),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat('EEE d MMM yyyy').format(day)} · ${byDay[day]!.length} ${byDay[day]!.length == 1 ? 'dose' : 'doses'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        for (final e in byDay[day]!)
                          Text(
                            '• ${DateFormat.jm().format(e.occurredAt)}${_overrideNote(e)}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Shared: ${facts.join(' · ')}',
            style: const TextStyle(color: muted, fontSize: 12, height: 1.4),
          ),
          if (sample.normalizedNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '"${sample.normalizedNote}"',
                style: const TextStyle(color: muted, fontSize: 12, height: 1.4),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (resetsLeanTimer ? red : toxic).withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (resetsLeanTimer ? red : toxic).withValues(alpha: .5),
              ),
            ),
            child: Text(
              resetsLeanTimer
                  ? 'Your clean time will count from the latest of these days. Everything you built before stays in your history.'
                  : 'Benzo-only use is saved for your safety log. It does not reset your lean clean time.',
              key: const ValueKey('multi-day-timer-note'),
              style: const TextStyle(height: 1.4, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('confirm-multi-day'),
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: cyan,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(50),
            ),
            icon: const Icon(Icons.playlist_add_check),
            label: Text(label),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('GO BACK'),
          ),
        ],
      ),
    );
  }
}
