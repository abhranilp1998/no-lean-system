import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/craving_entry.dart';
import '../domain/craving_wave.dart';

/// Ride a craving out: an animated wave, quick "It's N / Still N / It passed"
/// logging, and how long the last one took to pass, from real logs.
class CravingWaveScreen extends ConsumerStatefulWidget {
  const CravingWaveScreen({super.key, this.source = 'app'});

  final String source;

  static Future<void> open(BuildContext context, {String source = 'app'}) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CravingWaveScreen(source: source)),
      );

  @override
  ConsumerState<CravingWaveScreen> createState() => _CravingWaveScreenState();
}

class _CravingWaveScreenState extends ConsumerState<CravingWaveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  String? _cravingId;
  DateTime? _startedAt;
  int _level = 5;
  int? _passedIn;
  bool _busy = false;

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _run(() async {
    final now = DateTime.now();
    final id = await ref
        .read(recoveryProvider)
        .recordCraving(
          CravingEntry(
            intensity: _level,
            trigger: 'Other',
            note: 'Wave (${widget.source})',
            createdAt: now,
          ),
        );
    setState(() {
      _cravingId = id;
      _startedAt = now;
    });
  });

  Future<void> _check(int intensity) => _run(() async {
    final id = _cravingId!;
    await ref
        .read(recoveryProvider)
        .recordCravingCheck(cravingId: id, intensity: intensity);
    if (intensity == 0) {
      final minutes = DateTime.now().difference(_startedAt!).inMinutes;
      setState(() => _passedIn = max(1, minutes));
    }
  });

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(recoveryProvider);
    final history = CravingWaveHistory.fromEvents(controller.events);
    final points = _cravingId == null
        ? <WavePoint>[WavePoint(0, _level)]
        : CravingWaveHistory.pointsFor(controller.events, _cravingId!);
    final last = history.lastPassedMinutes;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ride the wave')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                last == null
                    ? 'Cravings rise, peak and fall. Log it and watch it pass.'
                    : 'Last time this passed in $last min.',
                key: const Key('wave-last-time'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) => CustomPaint(
                    painter: CravingWavePainter(
                      points: points,
                      phase: _motion.value,
                      expectedMinutes: (last ?? 15).toDouble(),
                      color: theme.colorScheme.primary,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_passedIn != null)
                Text(
                  'It passed in $_passedIn min. You rode it out.',
                  key: const Key('wave-passed'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                )
              else ...[
                Text('How strong: $_level / 10', textAlign: TextAlign.center),
                Slider(
                  value: _level.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$_level',
                  onChanged: (v) => setState(() => _level = v.round()),
                ),
                if (_cravingId == null)
                  FilledButton(
                    key: const Key('wave-start'),
                    onPressed: _busy ? null : _start,
                    child: Text("It's $_level"),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('wave-still'),
                          onPressed: _busy ? null : () => _check(_level),
                          child: Text('Still $_level'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const Key('wave-passed-button'),
                          onPressed: _busy ? null : () => _check(0),
                          child: const Text('It passed'),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Logged points as a solid line, then a dashed projection that falls back to
/// zero around [expectedMinutes]. A gentle moving swell keeps it alive.
class CravingWavePainter extends CustomPainter {
  CravingWavePainter({
    required this.points,
    required this.phase,
    required this.expectedMinutes,
    required this.color,
  });

  final List<WavePoint> points;
  final double phase;
  final double expectedMinutes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.isEmpty) return;
    final span = max(expectedMinutes * 1.4, points.last.minute + 5);
    Offset at(double minute, double intensity) => Offset(
      size.width * minute / span,
      size.height * (1 - intensity / 10.5),
    );
    final swell = sin(phase * 2 * pi) * 0.25;
    final line = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final logged = Path()..moveTo(at(points.first.minute, 0).dx, at(0, 0).dy);
    for (final p in points) {
      final o = at(p.minute, p.intensity + (p == points.last ? swell : 0));
      logged.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(logged, line);
    final tail = points.last;
    if (tail.intensity > 0) {
      final projected = Path()
        ..moveTo(
          at(tail.minute, tail.intensity.toDouble()).dx,
          at(tail.minute, tail.intensity.toDouble()).dy,
        );
      final end = max(expectedMinutes, tail.minute + 3);
      for (var i = 1; i <= 24; i++) {
        final m = tail.minute + (end - tail.minute) * i / 24;
        final fall = cos((i / 24) * pi / 2);
        final o = at(m, tail.intensity * fall + swell * fall);
        projected.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        projected,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
    }
    final dot = at(tail.minute, tail.intensity + swell);
    canvas.drawCircle(dot, 8 + 3 * (0.5 + swell), Paint()..color = color);
  }

  @override
  bool shouldRepaint(CravingWavePainter old) =>
      old.phase != phase || old.points != points;
}
