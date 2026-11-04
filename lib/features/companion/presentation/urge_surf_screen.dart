import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../recovery/application/recovery_provider.dart';
import 'companion_common.dart';

/// 20-minute urge-surf timer: rate at start, watch the wave, rate at end.
class UrgeSurfScreen extends ConsumerStatefulWidget {
  const UrgeSurfScreen({super.key, this.minutes = 20});
  final int minutes;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const UrgeSurfScreen()));

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
  int? _after;
  Duration _left = Duration.zero;

  @override
  void dispose() {
    _tick?.cancel();
    _wave.dispose();
    super.dispose();
  }

  void _go() {
    setState(() {
      _start = DateTime.now();
      _left = Duration(minutes: widget.minutes);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final left =
          Duration(minutes: widget.minutes) -
          DateTime.now().difference(_start!);
      setState(() => _left = left.isNegative ? Duration.zero : left);
      if (left.isNegative) _tick?.cancel();
    });
  }

  String get _phase {
    if (_start == null) return '';
    final done = 1 - _left.inSeconds / (widget.minutes * 60);
    if (done < .3) return 'Rising. Breathe out slowly. You do not have to act.';
    if (done < .6) return 'Peak. This is the strongest it gets. Stay with it.';
    if (done < 1) return 'Falling. Notice it getting quieter.';
    return 'You rode it out.';
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final running = _start != null && _left > Duration.zero;
    final finished = _start != null && _left == Duration.zero;
    final mm = _left.inMinutes.toString().padLeft(2, '0');
    final ss = (_left.inSeconds % 60).toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: const Text('Ride the wave')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Cravings usually rise and fall within about 15 to 30 minutes. '
            'You watch it, you do not have to obey it.',
            style: TextStyle(height: 1.35),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: AnimatedBuilder(
              animation: _wave,
              builder: (_, _) => CustomPaint(
                painter: _WavePainter(
                  _wave.value,
                  _start == null
                      ? 0
                      : 1 - _left.inSeconds / (widget.minutes * 60),
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_start == null) ...[
            Text('How strong is it right now? $_before / 10'),
            Slider(
              value: _before.toDouble(),
              max: 10,
              divisions: 10,
              onChanged: (v) => setState(() => _before = v.round()),
            ),
            FilledButton.icon(
              onPressed: _go,
              icon: const Icon(Icons.waves),
              label: Text('Start ${widget.minutes}-minute timer'),
            ),
          ],
          if (running) ...[
            Center(
              child: Text(
                '$mm:$ss',
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Center(child: Text(_phase, textAlign: TextAlign.center)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() {
                _tick?.cancel();
                _left = Duration.zero;
              }),
              child: const Text('It already passed'),
            ),
            TextButton.icon(
              onPressed: () => showReachOutSheet(context, ref, recovery),
              icon: const Icon(Icons.sms_outlined),
              label: const Text('Text my person while I wait'),
            ),
          ],
          if (finished) ...[
            Text('How strong is it now? ${_after ?? _before} / 10'),
            Slider(
              value: (_after ?? _before).toDouble(),
              max: 10,
              divisions: 10,
              onChanged: (v) => setState(() => _after = v.round()),
            ),
            Text(
              (_after ?? _before) < _before
                  ? 'From $_before to ${_after ?? _before}. That is the wave falling, and you stayed on the board.'
                  : 'Still strong? That happens. Start another round, or message your person.',
              style: const TextStyle(color: toxic, height: 1.35),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () async {
                await recovery.updateCompanion(
                  (s) =>
                      s.rate('i11', wasHelpful: (_after ?? _before) < _before),
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _start = null;
                _after = null;
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
