import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// One finished recording.
class VoiceTake {
  const VoiceTake(this.bytes, this.length);

  final Uint8List bytes;
  final Duration length;
}

abstract interface class VoiceRecorder {
  /// Asks for the microphone. Called only when the user taps "record a voice
  /// note": the app never asks for it anywhere else. False if refused.
  Future<bool> requestPermission();

  Future<void> start();

  /// Stops and returns the recording, or null if nothing was captured.
  Future<VoiceTake?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();

  Future<void> dispose();
}

abstract interface class VoicePlayer {
  Future<void> play(Uint8List bytes);

  Future<void> stop();

  /// Fires when playback reaches the end.
  Stream<void> get onComplete;

  Future<void> dispose();
}

/// AAC in an .m4a container, mono, 22.05 kHz, 48 kbit/s: clear speech at about
/// 360 KB for the full 60 seconds.
class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;
  DateTime? _startedAt;

  @override
  Future<bool> requestPermission() async {
    try {
      // `hasPermission` shows the system prompt the first time.
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/nl_note_${DateTime.now().microsecondsSinceEpoch}.m4a';
    _path = path;
    _startedAt = DateTime.now();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 48000,
        sampleRate: 22050,
        numChannels: 1,
      ),
      path: path,
    );
  }

  @override
  Future<VoiceTake?> stop() async {
    final started = _startedAt;
    final stopped = await _recorder.stop();
    final path = stopped ?? _path;
    _path = null;
    _startedAt = null;
    if (path == null) return null;
    final file = File(path);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return VoiceTake(
        bytes,
        started == null ? Duration.zero : DateTime.now().difference(started),
      );
    } finally {
      // The temporary recording is unencrypted; it never outlives this call.
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        /* Best effort. */
      }
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await stop();
    } catch (_) {
      /* Nothing to keep. */
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {
      /* Already released. */
    }
  }
}

/// Plays from memory: decrypted audio is never written back to disk.
class AudioplayersVoicePlayer implements VoicePlayer {
  AudioplayersVoicePlayer([AudioPlayer? player])
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Future<void> play(Uint8List bytes) =>
      _player.play(BytesSource(bytes, mimeType: 'audio/mp4'));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Overridable in tests so no widget touches the microphone or speakers.
final voiceRecorderFactoryProvider = Provider<VoiceRecorder Function()>(
  (ref) => RecordVoiceRecorder.new,
);

final voicePlayerFactoryProvider = Provider<VoicePlayer Function()>(
  (ref) => AudioplayersVoicePlayer.new,
);
