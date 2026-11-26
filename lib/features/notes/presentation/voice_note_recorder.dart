import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../letters/domain/future_letter.dart';
import '../services/voice_io.dart';

enum _Stage { idle, recording, review, denied }

/// Record a voice note of up to 60 seconds. The microphone permission is only
/// requested when the user taps RECORD; the mic is open only while recording.
class VoiceNoteRecorder extends ConsumerStatefulWidget {
  const VoiceNoteRecorder({
    required this.onSave,
    this.now = DateTime.now,
    super.key,
  });

  /// Test seam for the 60-second cap.
  final DateTime Function() now;

  /// Called with the finished take. May throw; the message is shown.
  final Future<void> Function(VoiceTake take) onSave;

  @override
  ConsumerState<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends ConsumerState<VoiceNoteRecorder>
    with WidgetsBindingObserver {
  VoiceRecorder? _recorder;
  VoicePlayer? _player;
  StreamSubscription<void>? _done;
  Timer? _tick;
  DateTime? _startedAt;
  Duration _stoppedAt = Duration.zero;
  _Stage _stage = _Stage.idle;
  VoiceTake? _take;
  bool _playing = false;
  bool _saving = false;
  String? _error;

  Duration get _max => VoiceClip.maxDuration;

  Duration get _elapsed => _stage == _Stage.recording && _startedAt != null
      ? widget.now().difference(_startedAt!)
      : _stoppedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _done?.cancel();
    final recorder = _recorder;
    if (recorder != null) {
      unawaited(recorder.cancel().then((_) => recorder.dispose()));
    }
    unawaited(_player?.dispose());
    super.dispose();
  }

  /// A phone call or app switch ends the recording but keeps what was said.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _stage == _Stage.recording) {
      unawaited(_stop());
    }
  }

  Future<void> _record() async {
    final recorder = _recorder ??= ref.read(voiceRecorderFactoryProvider)();
    setState(() => _error = null);
    final granted = await recorder.requestPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _stage = _Stage.denied);
      return;
    }
    try {
      await recorder.start();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = 'Could not start the microphone. Try again.';
      });
      return;
    }
    _startedAt = widget.now();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      if (_elapsed >= _max) {
        unawaited(_stop());
      } else {
        setState(() {});
      }
    });
    setState(() => _stage = _Stage.recording);
  }

  Future<void> _stop() async {
    if (_stage != _Stage.recording) return;
    _tick?.cancel();
    final elapsed = _elapsed;
    _stoppedAt = elapsed;
    final take = await _recorder?.stop();
    if (!mounted) return;
    if (take == null) {
      setState(() {
        _stage = _Stage.idle;
        _error = 'Nothing was recorded. Try again.';
      });
      return;
    }
    final length = take.length > Duration.zero ? take.length : elapsed;
    setState(() {
      _take = VoiceTake(take.bytes, length > _max ? _max : length);
      _stage = _Stage.review;
    });
  }

  Future<void> _listen() async {
    final take = _take;
    if (take == null) return;
    final player = _player ??= ref.read(voicePlayerFactoryProvider)();
    _done ??= player.onComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    if (_playing) {
      await player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    try {
      await player.play(take.bytes);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _save() async {
    final take = _take;
    if (take == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _player?.stop();
      await widget.onSave(take);
      if (!mounted) return;
      setState(() {
        _take = null;
        _playing = false;
        _stage = _Stage.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard() {
    unawaited(_player?.stop());
    setState(() {
      _take = null;
      _playing = false;
      _stage = _Stage.idle;
    });
  }

  String _clockText(Duration d) {
    final s = d.inSeconds.clamp(0, 60);
    return '0:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (_stage) {
          _Stage.idle => OutlinedButton.icon(
            key: const Key('voice-record'),
            icon: const Icon(Icons.mic_none),
            label: const Text('RECORD A VOICE NOTE (UP TO 60 S)'),
            onPressed: _record,
          ),
          _Stage.denied => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The microphone is off for NO LEAN, so voice notes cannot be '
                'recorded. Writing a note works without it. To record, allow '
                'the microphone for NO LEAN in your phone settings.',
                key: const Key('voice-denied'),
                style: theme.textTheme.bodyMedium,
              ),
              TextButton(
                key: const Key('voice-try-again'),
                onPressed: _record,
                child: const Text('TRY AGAIN'),
              ),
            ],
          ),
          _Stage.recording => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.fiber_manual_record, color: red, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'RECORDING  ${_clockText(_elapsed)} / 1:00',
                    key: const Key('voice-clock'),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (_elapsed.inMilliseconds / _max.inMilliseconds)
                    .clamp(0, 1)
                    .toDouble(),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('voice-stop'),
                icon: const Icon(Icons.stop),
                label: const Text('STOP'),
                onPressed: _stop,
              ),
            ],
          ),
          _Stage.review => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recorded ${_clockText(_take!.length)}. Listen, then keep it or '
                'try again.',
                key: const Key('voice-review'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const Key('voice-listen'),
                    icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                    label: Text(_playing ? 'STOP' : 'LISTEN'),
                    onPressed: _listen,
                  ),
                  TextButton(
                    key: const Key('voice-redo'),
                    onPressed: _saving ? null : _discard,
                    child: const Text('RE-RECORD'),
                  ),
                  FilledButton(
                    key: const Key('voice-save'),
                    onPressed: _saving ? null : _save,
                    child: const Text('KEEP IT'),
                  ),
                ],
              ),
            ],
          ),
        },
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}
