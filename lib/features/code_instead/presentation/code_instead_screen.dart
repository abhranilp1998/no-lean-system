import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/services/notification_service.dart';
import '../domain/code_tasks.dart';

enum _Phase { picking, running, done }

/// Code Instead: a rotating task and a focus timer. Every block that ends
/// (time up, task done, or stopped after a minute) lands in the history as a
/// `codeSession` event.
class CodeInsteadScreen extends ConsumerStatefulWidget {
  const CodeInsteadScreen({required this.source, this.clock, super.key});

  /// Where it was opened from: dashboard, widget or notification.
  final String source;

  /// Test hook; defaults to [DateTime.now].
  final DateTime Function()? clock;

  static Future<void> open(BuildContext context, {required String source}) =>
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CodeInsteadScreen(source: source)),
      );

  @override
  ConsumerState<CodeInsteadScreen> createState() => _CodeInsteadScreenState();
}

class _CodeInsteadScreenState extends ConsumerState<CodeInsteadScreen> {
  late final RecoveryController _recovery;
  Timer? _ticker;
  var _phase = _Phase.picking;
  var _skip = 0;
  var _minutes = defaultCodeBlockMinutes;
  late CodeTask _task;
  DateTime? _startedAt;
  DateTime? _endsAt;
  bool _recorded = false;
  bool _completed = false;
  bool _disposed = false;

  /// False from the start of dispose: no setState or notices after that.
  bool get _alive => mounted && !_disposed;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _recovery = ref.read(recoveryProvider);
    _task = nextCodeTask(_recovery.events);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    if (_phase == _Phase.running) {
      // Leaving mid-block counts as stopping it.
      unawaited(_finish(completed: false, notify: false));
    }
    super.dispose();
  }

  Duration get _planned => Duration(minutes: _minutes);

  Duration get _remaining {
    final endsAt = _endsAt;
    if (endsAt == null) return _planned;
    final left = endsAt.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  void _skipTask() {
    AppFeedback.selection();
    setState(() {
      _skip++;
      _task = nextCodeTask(_recovery.events, skip: _skip);
    });
  }

  void _start() {
    AppFeedback.tap();
    final now = _now();
    setState(() {
      _phase = _Phase.running;
      _startedAt = now;
      _endsAt = now.add(_planned);
      _recorded = false;
    });
    unawaited(
      NotificationService.instance.scheduleCodeTimer(
        endsAt: _endsAt!,
        task: _task.text,
      ),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_alive) return;
      if (_remaining == Duration.zero) {
        unawaited(_finish(completed: true));
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _finish({required bool completed, bool notify = true}) async {
    if (_phase != _Phase.running) return;
    _ticker?.cancel();
    unawaited(NotificationService.instance.cancelCodeTimer());
    final startedAt = _startedAt!;
    final endsAt = _endsAt!;
    final now = _now();
    final at = now.isAfter(endsAt) ? endsAt : now;
    final elapsed = at.difference(startedAt);
    _phase = _Phase.done;
    _completed = completed;
    if (_alive) setState(() {});
    if (completed) AppFeedback.success();

    if (!completed && elapsed < minRecordedCodeSession) {
      if (notify) _notice('STOPPED UNDER A MINUTE // NOT LOGGED.');
      return;
    }
    try {
      await _recovery.recordCodeSession(
        at: at,
        metadata: codeSessionMetadata(
          task: _task,
          planned: _planned,
          elapsed: elapsed,
          completed: completed,
          source: widget.source,
        ),
      );
      _recorded = true;
      if (_alive) setState(() {});
      if (notify) {
        _notice(
          completed
              ? 'BLOCK LOGGED // ${elapsed.inMinutes} MIN OF CODE, NOT LEAN.'
              : 'BLOCK LOGGED AS STOPPED // ${elapsed.inMinutes} MIN.',
          type: AppNoticeType.success,
        );
      }
    } catch (_) {
      if (notify) {
        _notice(
          'This block could not be saved. Your history is unchanged.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  void _notice(String message, {AppNoticeType type = AppNoticeType.info}) {
    if (!_alive) return;
    AppNotice.show(context, message, type: type);
  }

  void _again() {
    setState(() {
      _phase = _Phase.picking;
      _skip = 0;
      _startedAt = null;
      _endsAt = null;
      _task = nextCodeTask(_recovery.events);
    });
  }

  String _clock(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CODE INSTEAD')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
          children: [
            GlassCard(
              accent: purple,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusPill(
                      label: switch (_phase) {
                        _Phase.picking => 'NEXT TASK',
                        _Phase.running => 'BLOCK RUNNING',
                        _Phase.done =>
                          _completed ? 'BLOCK DONE' : 'BLOCK STOPPED',
                      },
                      color: purple,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _task.text,
                      key: const ValueKey('code-task'),
                      style: const TextStyle(fontSize: 15, height: 1.45),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        _clock(_remaining),
                        key: const ValueKey('code-countdown'),
                        style: displayFont(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            ..._controls(),
          ],
        ),
      ),
    );
  }

  List<Widget> _controls() => switch (_phase) {
    _Phase.picking => [
      Wrap(
        spacing: 8,
        children: [
          for (final minutes in codeBlockMinutes)
            ChoiceChip(
              key: ValueKey('code-minutes-$minutes'),
              label: Text('$minutes MIN'),
              selected: _minutes == minutes,
              selectedColor: purple.withValues(alpha: .3),
              onSelected: (_) => setState(() => _minutes = minutes),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('code-skip'),
              onPressed: _skipTask,
              child: const Text('OTHER TASK'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              key: const ValueKey('code-start'),
              onPressed: _start,
              style: FilledButton.styleFrom(backgroundColor: purple),
              child: const Text('START'),
            ),
          ),
        ],
      ),
    ],
    _Phase.running => [
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('code-stop'),
              onPressed: () => _finish(completed: false),
              child: const Text('STOP'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              key: const ValueKey('code-done'),
              onPressed: () => _finish(completed: true),
              style: FilledButton.styleFrom(backgroundColor: purple),
              child: const Text('TASK DONE'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        'Leave the app if you need to: a notification marks the end, '
        'unless quiet hours are on.',
        style: TextStyle(color: muted, fontSize: 11, height: 1.4),
      ),
    ],
    _Phase.done => [
      if (_recorded)
        const Text(
          'Logged in your timeline.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('code-close'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('CLOSE'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              key: const ValueKey('code-again'),
              onPressed: _again,
              style: FilledButton.styleFrom(backgroundColor: purple),
              child: const Text('ANOTHER BLOCK'),
            ),
          ),
        ],
      ),
    ],
  };
}
