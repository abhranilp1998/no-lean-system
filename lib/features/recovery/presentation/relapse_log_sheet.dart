import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../application/recovery_controller.dart';
import '../application/recovery_provider.dart';
import 'relapse_auth_dialog.dart';

Future<void> showRelapseLogSheet(
  BuildContext context, {
  String source = 'app',
}) async {
  final count = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RelapseLogSheet(source: source),
  );
  if (count != null && context.mounted) {
    AppNotice.show(
      context,
      '$count ${count == 1 ? 'event' : 'events'} saved. Take the next step at your own pace.',
      type: AppNoticeType.success,
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
  final _dates = <DateTime>[DateTime.now()];
  final _operationId = const Uuid().v4();
  bool _saving = false;
  String? _error;

  Future<void> _pickDate(int index) async {
    final current = _dates[index];
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date != null && mounted) {
      setState(() {
        _dates[index] = DateTime(
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
    final current = _dates[index];
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time != null && mounted) {
      setState(() {
        _dates[index] = DateTime(
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

  Future<void> _save() async {
    if (_saving) return;
    if (_dates.any((date) => date.isAfter(DateTime.now()))) {
      setState(
        () => _error =
            'An event cannot be in the future. Check each date and time.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final recovery = ref.read(recoveryProvider);
      var result = await recovery.recordRelapse(
        occurredAt: _dates,
        operationId: _operationId,
        source: widget.source,
      );
      if (!mounted) return;
      if (result == ProtectedActionResult.authenticationRequired) {
        final pin = await showRelapsePinDialog(
          context,
          actionLabel: 'SAVE EVENTS',
        );
        if (!mounted || pin == null) return;
        result = await recovery.recordRelapse(
          occurredAt: _dates,
          operationId: _operationId,
          source: widget.source,
          pin: pin,
          tryBiometrics: false,
        );
      }
      if (!mounted) return;
      if (result == ProtectedActionResult.completed) {
        Navigator.pop(context, _dates.length);
      } else {
        setState(
          () => _error =
              'Authentication failed. Your events have not been saved.',
        );
      }
    } on RecoverySaveException catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save these events. Check the dates and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .86,
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
                  child: ListView(
                    children: [
                      Text(
                        'LOG RELAPSES',
                        style: displayFont(fontSize: 22, color: cyan),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Welcome back. A setback does not erase your progress. Add one entry for each event, including anything you missed while away.',
                        style: TextStyle(height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Dates and times are local to this device. Clean time uses your latest recorded event. Existing history stays in place.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      for (var index = 0; index < _dates.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'EVENT ${index + 1}',
                                        style: eyebrowStyle,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove event ${index + 1}',
                                      onPressed: _saving || _dates.length == 1
                                          ? null
                                          : () => setState(
                                              () => _dates.removeAt(index),
                                            ),
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
                                      onPressed: _saving
                                          ? null
                                          : () => _pickDate(index),
                                      icon: const Icon(Icons.calendar_month),
                                      label: Text(
                                        DateFormat.yMMMd().format(
                                          _dates[index],
                                        ),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      key: ValueKey('relapse-time-$index'),
                                      onPressed: _saving
                                          ? null
                                          : () => _pickTime(index),
                                      icon: const Icon(Icons.schedule),
                                      label: Text(
                                        DateFormat.jm().format(_dates[index]),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving || _dates.length >= 50
                      ? null
                      : () => setState(() => _dates.add(DateTime.now())),
                  icon: const Icon(Icons.add),
                  label: const Text('ADD ANOTHER EVENT'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: const TextStyle(color: red)),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _saving
                        ? 'SAVING…'
                        : 'SAVE ${_dates.length} ${_dates.length == 1 ? 'EVENT' : 'EVENTS'}',
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
