import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recovery/application/recovery_provider.dart';
import '../../recovery/services/notification_service.dart';
import '../domain/position_status.dart';
import '../domain/zone_presence.dart';
import '../services/location_service.dart';

/// Where the position status goes. Behind an interface for tests.
abstract interface class PositionStatusSink {
  Future<void> show(PositionStatusText text);
  Future<void> cancel();
}

class NotificationPositionStatusSink implements PositionStatusSink {
  const NotificationPositionStatusSink();

  @override
  Future<void> show(PositionStatusText text) => NotificationService.instance
      .showPositionStatus(title: text.title, body: text.body);

  @override
  Future<void> cancel() => NotificationService.instance.cancelPositionStatus();
}

final positionStatusSinkProvider = Provider<PositionStatusSink>(
  (ref) => const NotificationPositionStatusSink(),
);

/// Keeps the always-on "Position status" notification in sync while NO LEAN
/// is open (foreground). Wraps the shell without changing it.
///
/// - Starts on open/resume, cancels on pause/hide/detach and on dispose.
/// - Reads position with the existing [LocationService] (foreground only,
///   never requests permission itself) and re-checks access every
///   [refreshInterval], so "location off" / "no permission" show up too.
/// - Posts through [PositionStatusThrottle]: immediately on a state change,
///   otherwise at most every 15 s.
/// - Independent of zone alerts: it neither reads nor feeds the zone
///   presence tracker, quiet hours or alert de-duplication.
class PositionStatusHost extends ConsumerStatefulWidget {
  const PositionStatusHost({
    required this.child,
    this.refreshInterval = const Duration(seconds: 15),
    super.key,
  });

  final Widget child;
  final Duration refreshInterval;

  @override
  ConsumerState<PositionStatusHost> createState() => _PositionStatusHostState();
}

class _PositionStatusHostState extends ConsumerState<PositionStatusHost>
    with WidgetsBindingObserver {
  late final PositionStatusThrottle _throttle = PositionStatusThrottle(
    minInterval: widget.refreshInterval,
  );
  StreamSubscription<LocationFix>? _subscription;
  Timer? _ticker;
  LocationAccess? _access;
  LocationFix? _fix;
  bool _foreground = true;
  bool _active = false;
  bool _refreshing = false;
  bool _posted = false;
  bool _streamFailed = false;
  late final PositionStatusSink _sink = ref.read(positionStatusSinkProvider);

  @override
  void initState() {
    super.initState();
    _sink;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop(cancelNotification: true);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
      case AppLifecycleState.inactive:
        // Notification shade, permission dialogs, split screen: still open.
        return;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _foreground = false;
    }
    _sync();
  }

  bool get _enabled {
    final recovery = ref.read(recoveryProvider);
    return recovery.isLoaded && recovery.positionNotification;
  }

  void _sync() {
    if (!mounted) return;
    final shouldRun = _foreground && _enabled;
    if (shouldRun && !_active) {
      _active = true;
      _ticker = Timer.periodic(widget.refreshInterval, (_) {
        _streamFailed = false;
        unawaited(_refresh());
      });
      unawaited(_refresh());
    } else if (!shouldRun && _active) {
      _stop(cancelNotification: true);
    } else if (shouldRun) {
      _publish();
    }
  }

  void _stop({required bool cancelNotification}) {
    _active = false;
    _ticker?.cancel();
    _ticker = null;
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    _throttle.reset();
    _streamFailed = false;
    _fix = null;
    if (cancelNotification && _posted) {
      _posted = false;
      unawaited(_sink.cancel());
    }
  }

  static bool _granted(LocationAccess? access) =>
      access == LocationAccess.whileInUse || access == LocationAccess.always;

  Future<void> _refresh() async {
    if (!_active || _refreshing) return;
    _refreshing = true;
    try {
      final location = ref.read(locationServiceProvider);
      final access = await location.access();
      if (!_active || !mounted) return;
      _access = access;
      if (_granted(access)) {
        if (_subscription == null && !_streamFailed) {
          _subscription = location.fixes().listen(
            _onFix,
            onError: (Object _) => _onStreamError(),
            cancelOnError: true,
          );
          // Show something right away instead of waiting for movement.
          unawaited(
            location.currentFix().then((fix) {
              if (fix != null && _active && _fix == null) _onFix(fix);
            }),
          );
        }
      } else {
        final subscription = _subscription;
        _subscription = null;
        await subscription?.cancel();
        _fix = null;
      }
      _publish();
    } catch (_) {
      // Indicator only; retry on the next tick.
    } finally {
      _refreshing = false;
    }
  }

  void _onFix(LocationFix fix) {
    if (!_active) return;
    _fix = fix;
    _publish();
  }

  void _onStreamError() {
    _subscription = null;
    _fix = null;
    // Usually location was switched off: re-check access now, but only
    // re-subscribe on the next tick so a failing stream cannot spin.
    _streamFailed = true;
    unawaited(_refresh());
  }

  PositionAvailability get _availability => switch (_access) {
    LocationAccess.serviceDisabled => PositionAvailability.locationOff,
    LocationAccess.denied ||
    LocationAccess.deniedForever => PositionAvailability.noPermission,
    LocationAccess.whileInUse || LocationAccess.always =>
      _fix == null ? PositionAvailability.locating : PositionAvailability.fix,
    null => PositionAvailability.locating,
  };

  void _publish() {
    if (!_active || !mounted) return;
    final recovery = ref.read(recoveryProvider);
    final text = buildPositionStatusText(
      availability: _availability,
      zones: recovery.zones,
      hideSensitive: recovery.notificationPrefs.hideSensitive,
      fix: _fix,
    );
    if (!_throttle.shouldPost(text, DateTime.now())) return;
    _posted = true;
    unawaited(_sink.show(text));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(recoveryProvider, (_, _) => _sync());
    return widget.child;
  }
}
