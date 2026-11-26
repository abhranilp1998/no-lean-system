import 'package:flutter/material.dart';
import '../../features/emergency/domain/sos_text.dart';
import '../services/app_feedback.dart';

/// A press that is released before [duration] runs [onTap]; a press held
/// for the full duration runs [onHold] once, with a visible progress ring
/// and haptics. The hold never auto-repeats.
///
/// Used on SOS buttons: a short tap keeps today's behavior, a ~2 s hold
/// opens the prefilled text to the user's own SOS contact.
class HoldToAct extends StatefulWidget {
  const HoldToAct({
    required this.onTap,
    required this.onHold,
    required this.child,
    this.duration = sosHoldDuration,
    this.color,
    this.onHoldStart,
    this.enabled = true,
    super.key,
  });

  final VoidCallback onTap;
  final VoidCallback onHold;
  final Widget child;
  final Duration duration;
  final Color? color;
  final VoidCallback? onHoldStart;
  final bool enabled;

  @override
  State<HoldToAct> createState() => HoldToActState();
}

class HoldToActState extends State<HoldToAct>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int? _pointer;
  Offset? _origin;
  bool _fired = false;
  bool _cancelled = false;

  static const _slop = 28.0;

  double get progress => _ctrl.value;
  bool get isHolding => _ctrl.isAnimating || (_ctrl.value > 0 && !_fired);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(() {
        if (mounted) setState(() {});
        if (_ctrl.value >= 1 && !_fired && !_cancelled) {
          _fired = true;
          AppFeedback.success();
          widget.onHold();
        }
      });
  }

  @override
  void didUpdateWidget(HoldToAct oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) _ctrl.duration = widget.duration;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _start(PointerDownEvent event) {
    if (!widget.enabled) return;
    _pointer = event.pointer;
    _origin = event.position;
    _fired = false;
    _cancelled = false;
    AppFeedback.selection();
    widget.onHoldStart?.call();
    _ctrl.forward(from: 0);
  }

  void _move(PointerMoveEvent event) {
    if (_pointer != event.pointer || _origin == null || _fired) return;
    if ((event.position - _origin!).distance > _slop) _cancel(fireTap: false);
  }

  void _end(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    if (_fired || _cancelled) {
      _ctrl.value = 0;
      return;
    }
    _ctrl.stop();
    _ctrl.value = 0;
    widget.onTap();
  }

  void _cancel({required bool fireTap}) {
    if (_cancelled || _fired) return;
    _cancelled = true;
    _pointer = null;
    _ctrl.stop();
    _ctrl.value = 0;
    if (fireTap) widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.error;
    return Listener(
      key: const ValueKey('hold-to-act'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _start,
      onPointerMove: _move,
      onPointerUp: _end,
      onPointerCancel: (_) => _cancel(fireTap: false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The child is display-only; this wrapper owns the gesture.
          IgnorePointer(child: widget.child),
          if (progress > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const ValueKey('hold-to-act-progress'),
                  painter: HoldProgressPainter(
                    progress: progress,
                    color: color,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rounded-rect stroke that fills clockwise as the hold progresses.
class HoldProgressPainter extends CustomPainter {
  const HoldProgressPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(2),
      const Radius.circular(15),
    );
    final track = Paint()
      ..color = color.withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(rrect, track);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(HoldProgressPainter old) =>
      old.progress != progress || old.color != color;
}
