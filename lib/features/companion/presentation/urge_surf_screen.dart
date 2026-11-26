import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../cravings/domain/urge_ride.dart';
import '../../notes/domain/note_invite.dart';
import '../../notes/presentation/future_note_card.dart';
import '../../notes/presentation/note_invite_panel.dart';
import '../../recovery/application/recovery_provider.dart';
import 'companion_common.dart';

/// 10-minute ride-it-out timer, built on the existing urge-surf wave.
///
/// [open] and [openRideItOut] are the same entry. Rough-day mode (PR #34)
/// already calls [open] for "Ride it out"; once that PR is merged it will
/// pick this 10-minute flow up with no extra hook.
class UrgeSurfScreen extends ConsumerStatefulWidget {
  const UrgeSurfScreen({
    super.key,
    this.minutes = 10,
    this.onPace,
    this.now = DateTime.now,
  });

  final int minutes;

  /// Test seam: called on each breathing-phase change when haptic pacing
  /// is on. The real haptic goes through [AppFeedback].
  final void Function(BreathPhase phase)? onPace;

  /// Test seam so the timer can be advanced without waiting on the wall clock.
  final DateTime Function() now;

  static Future<void> open(BuildContext context) => openRideItOut(context);

  static Future<void> openRideItOut(
    BuildContext context, {
    int minutes = 10,
    void Function(BreathPhase phase)? onPace,
    DateTime Function() now = DateTime.now,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          UrgeSurfScreen(minutes: minutes, onPace: onPace, now: now),
    ),
  );

  @override
  ConsumerState<UrgeSurfScreen> createState() => _UrgeSurfState();
}

class _UrgeSurfState extends ConsumerState<UrgeSurfScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();
  Timer? _tick;
  DateTime? _start;
  int _before = 6;
  Duration _left = Duration.zero;
  bool _paceBreathing = true;
  BreathPhase? _lastPhase;
  UrgeRideOutcome? _outcome;
  UrgeRideActivity? _activity;
  bool _saving = false;

  int get _planned => widget.minutes;

  @override
  void dispose() {
    _tick?.cancel();
    _wave.dispose();
    super.dispose();
  }

  void _pulse(BreathPhase phase) {
    if (!_paceBreathing) return;
    if (!ref.read(recoveryProvider).hapticFeedback) return;
    widget.onPace?.call(phase);
    AppFeedback.selection();
  }

  void _go() {
    _tick?.cancel();
    setState(() {
      _start = widget.now();
      _left = Duration(minutes: _planned);
      _outcome = null;
      _activity = null;
      _lastPhase = breathPhaseAt(Duration.zero);
    });
    _pulse(_lastPhase!);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final elapsed = widget.now().difference(_start!);
      final left = Duration(minutes: _planned) - elapsed;
      final phase = breathPhaseAt(elapsed);
      setState(() => _left = left.isNegative ? Duration.zero : left);
      if (phase != _lastPhase) {
        _lastPhase = phase;
        _pulse(phase);
      }
      if (left.isNegative || left == Duration.zero) _tick?.cancel();
    });
  }

  void _finishEarly({UrgeRideOutcome? outcome}) {
    _tick?.cancel();
    setState(() {
      _left = Duration.zero;
      if (outcome != null) _outcome = outcome;
    });
  }

  String get _phase {
    if (_start == null) return '';
    if (_left == Duration.zero) return 'You stayed with it. That is the work.';
    final done = 1 - _left.inSeconds / (_planned * 60);
    if (done < .3) return 'Rising. Breathe out slowly. You do not have to act.';
    if (done < .6) return 'Peak. This is the strongest it gets. Stay with it.';
    return 'Falling. Notice it getting quieter.';
  }

  Future<void> _save() async {
    if (_saving || _outcome == null || _activity == null || _start == null) {
      return;
    }
    _saving = true;
    try {
      await ref
          .read(recoveryProvider)
          .recordUrgeRide(
            startedAt: _start!,
            outcome: _outcome!,
            activity: _activity!,
            hapticPacing: _paceBreathing,
            intensityBefore: _before,
            plannedMinutes: _planned,
          );
      if (!mounted) return;
      AppFeedback.success();
      AppNotice.show(
        context,
        _outcome == UrgeRideOutcome.no
            ? 'Logged. You stayed with it, and that still counts.'
            : 'Logged. That is data you can use next time.',
        type: AppNoticeType.success,
      );
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'Could not save that ride. Please try again.',
          type: AppNoticeType.error,
        );
      }
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final running = _start != null && _left > Duration.zero;
    final finished = _start != null && _left == Duration.zero;
    final mm = _left.inMinutes.toString().padLeft(2, '0');
    final ss = (_left.inSeconds % 60).toString().padLeft(2, '0');
    final canPace = recovery.hapticFeedback;
    return Scaffold(
      appBar: AppBar(title: const Text('Ride it out')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Ten minutes. You do not have to win it. You only have to stay with it.',
            style: TextStyle(height: 1.35, fontSize: 15),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: AnimatedBuilder(
              animation: _wave,
              builder: (_, _) => CustomPaint(
                painter: _WavePainter(
                  _wave.value,
                  _start == null ? 0 : 1 - _left.inSeconds / (_planned * 60),
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_start == null) ...[
            Text('How strong is it right now? $_before / 10'),
            Slider(
              key: const ValueKey('urge-ride-intensity'),
              value: _before.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (v) => setState(() => _before = v.round()),
            ),
            SwitchListTile(
              key: const ValueKey('urge-ride-haptic-toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Pace my breathing with a gentle haptic'),
              subtitle: Text(
                canPace
                    ? 'A soft pulse on each in-breath and out-breath.'
                    : 'Turn on vibration in Settings to use this.',
              ),
              value: _paceBreathing && canPace,
              onChanged: canPace
                  ? (v) => setState(() => _paceBreathing = v)
                  : null,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('urge-ride-start'),
              onPressed: _go,
              icon: const Icon(Icons.waves),
              label: Text('Start $_planned-minute timer'),
            ),
          ],
          if (running) ...[
            Center(
              child: Text(
                '$mm:$ss',
                key: const ValueKey('urge-ride-timer'),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (_paceBreathing && canPace)
              Center(
                child: Text(
                  breathPhaseLabel(_lastPhase ?? BreathPhase.inhale),
                  key: const ValueKey('urge-ride-breath'),
                  style: eyebrowStyle.copyWith(color: cyan, fontSize: 16),
                ),
              ),
            const SizedBox(height: 8),
            Center(child: Text(_phase, textAlign: TextAlign.center)),
            const SizedBox(height: 12),
            const FutureNoteCard(moment: NoteMoment.urge),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('urge-ride-already-passed'),
              onPressed: () => _finishEarly(outcome: UrgeRideOutcome.yes),
              child: const Text('It already passed'),
            ),
            TextButton.icon(
              onPressed: () => showReachOutSheet(context, ref, recovery),
              icon: const Icon(Icons.sms_outlined),
              label: const Text('Text my person while I wait'),
            ),
          ],
          if (finished) ...[
            Text(_phase, style: const TextStyle(height: 1.35, fontSize: 15)),
            const SizedBox(height: 16),
            const Text(
              'Did it pass?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final outcome in UrgeRideOutcome.values)
                  ChoiceChip(
                    key: ValueKey('urge-ride-passed-${outcome.name}'),
                    label: Text(outcome.label),
                    selected: _outcome == outcome,
                    onSelected: (_) => setState(() => _outcome = outcome),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'What did you use?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final activity in UrgeRideActivity.values)
                  ChoiceChip(
                    key: ValueKey('urge-ride-activity-${activity.name}'),
                    label: Text(activity.label),
                    selected: _activity == activity,
                    onSelected: (_) => setState(() => _activity = activity),
                  ),
              ],
            ),
            // The urge eased: invite a note for next time.
            if (_outcome == UrgeRideOutcome.yes ||
                _outcome == UrgeRideOutcome.aBit) ...[
              const SizedBox(height: 10),
              const FutureNoteInviteLink(
                occasion: NoteInviteOccasion.urgePassed,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('urge-ride-save'),
              onPressed: _outcome != null && _activity != null && !_saving
                  ? _save
                  : null,
              child: const Text('SAVE THIS RIDE'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _tick?.cancel();
                _start = null;
                _outcome = null;
                _activity = null;
                _left = Duration.zero;
              }),
              child: const Text('Another round'),
            ),
          ],
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.progress);
  final double t;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // Envelope: rises, peaks around 45%, falls.
    final env = math.sin(math.pi * progress.clamp(0, 1)).toDouble();
    final amp = size.height * (.12 + .3 * env);
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += 4) {
      final y =
          size.height * .6 -
          amp *
              math.sin((x / size.width * 2 * math.pi * 1.5) + t * 2 * math.pi);
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = cyan.withValues(alpha: .35));
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.t != t || old.progress != progress;
}
