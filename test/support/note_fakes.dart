import 'package:no_lean/features/notes/services/future_note_service.dart';
import 'package:no_lean/features/notes/services/note_vault.dart';
import 'package:no_lean/features/notes/services/voice_note_store.dart';

class MemoryNoteKeyStorage implements NoteKeyStorage {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Keystore unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// A "phone": secure storage + voice files. Make a second one to play a new
/// phone or a reinstall.
class FakePhone {
  FakePhone() {
    notes = FutureNoteService(
      vault: NoteVault(storage: keys, rounds: 1000),
      voice: voice,
    );
  }

  final keys = MemoryNoteKeyStorage();
  final voice = MemoryVoiceNoteStore();
  late final FutureNoteService notes;
}
