import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hold_to_act.dart';
import '../../zones/domain/zone_presence.dart';
import '../../zones/services/location_service.dart';
import '../application/sos_text_service.dart';
import '../domain/sos_text.dart';

/// Wraps an SOS button: a short press keeps [onTap] (usually open the SOS
/// screen); a ~2 s hold opens the phone's SMS composer to the user's own
/// contact, with a maps link if we have a fix. Never auto-sends.
class HoldToTextSos extends ConsumerStatefulWidget {
  const HoldToTextSos({
    required this.onTap,
    required this.child,
    this.color = red,
    this.duration = sosHoldDuration,
    this.launcher,
    this.resolveFix,
    this.now,
    super.key,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color color;
  final Duration duration;

  /// Test seams.
  final Future<bool> Function(Uri uri)? launcher;
  final Future<LocationFix?> Function()? resolveFix;
  final DateTime? now;

  @override
  ConsumerState<HoldToTextSos> createState() => _HoldToTextSosState();
}

class _HoldToTextSosState extends ConsumerState<HoldToTextSos> {
  Future<LocationFix?>? _prefetch;

  void _start() {
    final custom = widget.resolveFix;
    _prefetch = custom != null
        ? custom()
        : resolveSosFix(ref.read(locationServiceProvider));
  }

  void _open() {
    final pending = _prefetch;
    unawaited(
      holdToTextSos(
        context,
        ref,
        launcher: widget.launcher,
        now: widget.now,
        resolveFix: () async =>
            pending ??
            (widget.resolveFix != null
                ? await widget.resolveFix!()
                : await resolveSosFix(ref.read(locationServiceProvider))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HoldToAct(
      onTap: widget.onTap,
      onHold: _open,
      onHoldStart: _start,
      duration: widget.duration,
      color: widget.color,
      child: widget.child,
    );
  }
}

/// Callbacks for buttons that already expose [onHold] / [onHoldStart]
/// (GlowButton, ActionTile). Prefetches a GPS fix while the user holds.
class SosHoldBinding {
  SosHoldBinding(
    this.context,
    this.ref, {
    this.launcher,
    this.resolveFix,
    this.now,
  });

  final BuildContext context;
  final WidgetRef ref;
  final Future<bool> Function(Uri uri)? launcher;
  final Future<LocationFix?> Function()? resolveFix;
  final DateTime? now;

  // Shared so a new Binding instance in a rebuild still sees the prefetch
  // started on pointer-down (and so onHoldStart / onHold can be bound
  // from two one-liner closures).
  static Future<LocationFix?>? _prefetch;

  void start() {
    _prefetch = resolveFix != null
        ? resolveFix!()
        : resolveSosFix(ref.read(locationServiceProvider));
  }

  void open() {
    final pending = _prefetch;
    _prefetch = null;
    unawaited(
      holdToTextSos(
        context,
        ref,
        launcher: launcher,
        now: now,
        resolveFix: () async =>
            pending ??
            (resolveFix != null
                ? await resolveFix!()
                : await resolveSosFix(ref.read(locationServiceProvider))),
      ),
    );
  }
}
