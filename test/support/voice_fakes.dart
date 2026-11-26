import 'dart:async';
import 'dart:typed_data';

import 'package:no_lean/features/notes/services/voice_io.dart';

class FakeVoiceRecorder implements VoiceRecorder {
  bool allow = true;
  int permissionAsks = 0;
  bool recording = false;
  bool disposed = false;
  int stops = 0;
  Duration length = const Duration(seconds: 7);
  Uint8List bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
  bool emptyTake = false;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return allow;
  }

  @override
  Future<void> start() async => recording = true;

  @override
  Future<VoiceTake?> stop() async {
    recording = false;
    stops++;
    return emptyTake ? null : VoiceTake(bytes, length);
  }

  @override
  Future<void> cancel() async => recording = false;

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeVoicePlayer implements VoicePlayer {
  final played = <Uint8List>[];
  int stops = 0;
  final _done = StreamController<void>.broadcast();

  void finish() => _done.add(null);

  @override
  Stream<void> get onComplete => _done.stream;

  @override
  Future<void> play(Uint8List bytes) async => played.add(bytes);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {}
}
