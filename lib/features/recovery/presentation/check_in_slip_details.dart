import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glow_button.dart';
import '../application/recovery_controller.dart';
import '../application/recovery_provider.dart';
import '../domain/recovery_event.dart';
import '../domain/relapse_log_entry.dart';
import 'relapse_auth_dialog.dart';

/// Asks for details on a "Used" tapped on the daily check-in. Until the user
/// answers, the slip counts as lean. Safe to call again on the next open.
Future<void> showSlipDetailsPrompt(BuildContext context, RecoveryEvent slip) =>
    showDialog<void>(
      context: context,
      builder: (_) => SlipDetailsDialog(slip: slip),
    );

class SlipDetailsDialog extends ConsumerStatefulWidget {
  const SlipDetailsDialog({required this.slip, super.key});

  final RecoveryEvent slip;

  @override
  ConsumerState<SlipDetailsDialog> createState() => _SlipDetailsDialogState();
}

class _SlipDetailsDialogState extends ConsumerState<SlipDetailsDialog> {
  final _note = TextEditingController();
  RelapseType? _type;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save({RelapseType? type, bool keep = false}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final recovery = ref.read(recoveryProvider);
    var result = await recovery.completeSlipDetails(
      id: widget.slip.id,
      type: keep ? null : type,
      note: keep ? '' : _note.text,
    );
    if (result == ProtectedActionResult.authenticationRequired && mounted) {
      final pin = await showRelapsePinDialog(
        context,
        actionLabel: 'AUTHORIZE CHANGE',
      );
      if (pin == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      result = await recovery.completeSlipDetails(
        id: widget.slip.id,
        type: keep ? null : type,
        note: keep ? '' : _note.text,
        pin: pin,
        tryBiometrics: false,
      );
    }
    if (!mounted) return;
    if (result == ProtectedActionResult.completed) {
      Navigator.pop(context);
      AppNotice.show(
        context,
        keep ? 'KEPT AS LEAN. YOU CAN EDIT IT ANY TIME.' : 'DETAILS SAVED.',
        type: AppNoticeType.success,
      );
    } else {
      setState(() {
        _saving = false;
        _error = result == ProtectedActionResult.lockedOut
            ? result.failureMessage
            : 'Not changed. Authentication is needed for that choice.';
      });
    }
  }

  Future<void> _remove() async {
    if (_saving) return;
    final recovery = ref.read(recoveryProvider);
    var result = await recovery.deleteEvent(id: widget.slip.id);
    if (result == ProtectedActionResult.authenticationRequired && mounted) {
      final pin = await showRelapsePinDialog(
        context,
        actionLabel: 'REMOVE SLIP',
      );
      if (pin == null) return;
      result = await recovery.deleteEvent(
        id: widget.slip.id,
        pin: pin,
        tryBiometrics: false,
      );
    }
    if (!mounted) return;
    if (result == ProtectedActionResult.completed) {
      Navigator.pop(context);
      AppNotice.show(context, 'REMOVED.', type: AppNoticeType.success);
    } else {
      setState(() => _error = 'Not removed. Nothing was changed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final when = DateFormat('HH:mm').format(widget.slip.timestamp.toLocal());
    return Dialog(
      key: const ValueKey('slip-details-prompt'),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: magenta.withValues(alpha: .4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'WHAT WAS IT?',
                style: displayFont(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: magenta,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You tapped Used at $when. Thank you for telling the truth. '
                'Until you say what it was, it counts as lean.',
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 14),
              for (final type in RelapseType.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _TypeTile(
                    key: ValueKey('slip-type-${type.name}'),
                    label: type.label,
                    selected: _type == type,
                    onTap: () => setState(() => _type = type),
                  ),
                ),
              if (_type == RelapseType.benzo)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Benzo only: saved for safety checks, and your lean clean '
                    'time keeps counting from your last lean.',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('slip-note'),
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Optional note',
                  isDense: true,
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: red, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 14),
              GlowButton(
                key: const ValueKey('slip-save'),
                label: 'SAVE DETAILS',
                color: _type == null ? muted : cyan,
                onTap: () {
                  if (_type != null) _save(type: _type);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('slip-keep'),
                      onPressed: () => _save(keep: true),
                      child: const Text('KEEP AS LEAN'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      key: const ValueKey('slip-later'),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('LATER'),
                    ),
                  ),
                ],
              ),
              TextButton(
                key: const ValueKey('slip-remove'),
                onPressed: _remove,
                child: const Text('WRONG TAP // REMOVE IT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width choice that wraps its text, so large fonts never clip it.
class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? magenta.withValues(alpha: .18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? magenta : Colors.white24,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : muted,
                ),
              ),
            ),
            if (selected) const Icon(Icons.check, size: 16, color: magenta),
          ],
        ),
      ),
    ),
  );
}
