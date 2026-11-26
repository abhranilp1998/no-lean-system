import 'dart:convert';
import 'dart:typed_data';

import '../../letters/domain/future_letter.dart';
import '../domain/note_crypto.dart';
import 'note_vault.dart';
import 'voice_note_store.dart';

class NoteUnlockResult {
  const NoteUnlockResult({
    required this.letters,
    required this.opened,
    required this.stillLocked,
    required this.wrongPin,
  });

  final List<FutureLetter> letters;
  final int opened;
  final int stillLocked;

  /// The PIN opened none of the locked notes.
  final bool wrongPin;
}

/// Everything about notes at rest: sealing, opening, voice files, and the PIN
/// lifecycle. Pure with respect to app state: it takes lists of notes and
/// returns new ones, so the controller keeps one source of truth. Nothing here
/// throws on a bad key or a missing file; a note it cannot handle is returned
/// unchanged, never dropped.
class FutureNoteService {
  FutureNoteService({NoteVault? vault, VoiceNoteStore? voice})
    : vault = vault ?? NoteVault(),
      voice = voice ?? FileVoiceNoteStore();

  /// Plain-notes-only service (no secure storage).
  FutureNoteService.unavailable()
    : vault = NoteVault(storage: const UnavailableNoteKeyStorage()),
      voice = MemoryVoiceNoteStore();

  final NoteVault vault;
  final VoiceNoteStore voice;

  final List<(String, bool)> _maybeOrphaned = [];

  Future<bool> get encrypting async => (await vault.localKey()) != null;

  // --- creating -----------------------------------------------------------

  Future<FutureLetter> createText(String text, DateTime at) async {
    final plain = FutureLetter.create(text, at: at);
    final local = await vault.localKey();
    if (local == null) return plain;
    return await _sealLetter(plain, local) ?? plain;
  }

  Future<FutureLetter> createVoice(
    Uint8List bytes,
    Duration length,
    DateTime at,
  ) async {
    if (bytes.isEmpty) throw const FormatException('The recording is empty.');
    final capped = length > VoiceClip.maxDuration
        ? VoiceClip.maxDuration
        : length;
    final base = FutureLetter(
      id: FutureLetter.create('x', at: at).id,
      text: FutureLetter.voicePlaceholder,
      createdAt: at,
      audio: VoiceClip(durationMs: capped.inMilliseconds),
    );
    final local = await vault.localKey();
    final sealed = local == null ? null : await _sealVoice(base, bytes, local);
    if (sealed != null) return sealed;
    await voice.write(base.id, bytes, encrypted: false);
    _queueOrphans(base.id);
    return base;
  }

  // --- reading ------------------------------------------------------------

  Future<bool> isLocked(FutureLetter letter) async {
    if (letter.sealed != null) {
      return await vault.keyFor(letter.sealed!.keyId) == null;
    }
    final clip = letter.audio;
    if (clip != null && clip.isEncrypted) {
      return await vault.keyFor(clip.keyId!) == null;
    }
    return false;
  }

  /// The note's words, or null when it is locked, damaged, or a voice note.
  Future<String?> readText(FutureLetter letter) async {
    if (letter.isVoice) return null;
    final sealed = letter.sealed;
    if (sealed == null) return letter.text;
    final key = await vault.keyFor(sealed.keyId);
    if (key == null) return null;
    final bytes = await openBytes(sealed, key, noteAad(letter.id));
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  /// The recording's bytes, or null when locked, missing, or not a voice note.
  Future<Uint8List?> readAudio(FutureLetter letter) async {
    final clip = letter.audio;
    if (clip == null) return null;
    final raw = await voice.read(letter.id, encrypted: clip.isEncrypted);
    if (raw == null || !clip.isEncrypted) return raw;
    final key = await vault.keyFor(clip.keyId!);
    if (key == null) return null;
    return openBytes(
      SealedPayload(keyId: clip.keyId!, data: raw, wrap: clip.wrap),
      key,
      voiceAad(letter.id),
    );
  }

  /// The file as stored on this phone (still sealed if a PIN is set). Does
  /// not decrypt: a backup carries the bytes as they sit on disk.
  Future<Uint8List?> exportAudio(FutureLetter letter) async {
    final clip = letter.audio;
    if (clip == null) return null;
    return voice.read(letter.id, encrypted: clip.isEncrypted);
  }

  /// Writes imported recordings only when this phone has no file for that
  /// note. Never overwrites or deletes an existing recording — a backup
  /// without audio must not wipe what is already here.
  Future<void> importAudio(List<FutureLetter> imported) async {
    for (final letter in imported) {
      final bytes = letter.backupAudio;
      final clip = letter.audio;
      if (bytes == null || bytes.isEmpty || clip == null) continue;
      try {
        if (await voice.exists(letter.id, encrypted: true) ||
            await voice.exists(letter.id, encrypted: false)) {
          continue;
        }
        await voice.write(letter.id, bytes, encrypted: clip.isEncrypted);
      } catch (_) {
        /* The note itself is already saved; a missing file is recoverable. */
      }
    }
  }

  // --- PIN lifecycle ------------------------------------------------------

  /// A PIN was set or changed: make sure the key exists, wrapped under the new
  /// PIN, and every note is sealed under it with a fresh wrap. Returns the
  /// notes unchanged if secure storage is unusable.
  Future<List<FutureLetter>> activate(
    String pin,
    List<FutureLetter> letters,
  ) async {
    final local = await vault.enable(pin);
    if (local == null) return letters;
    return syncToKey(letters, local);
  }

  /// Seals plain notes and refreshes stale wraps for notes using this
  /// phone's key. Foreign-key notes are left for [unlock].
  Future<List<FutureLetter>> syncToKey(
    List<FutureLetter> letters, [
    LocalNoteKey? known,
  ]) async {
    final local = known ?? await vault.localKey();
    if (local == null) return letters;
    final out = <FutureLetter>[];
    for (final letter in letters) {
      out.add(await _syncOne(letter, local));
    }
    return out;
  }

  Future<FutureLetter> _syncOne(FutureLetter letter, LocalNoteKey local) async {
    try {
      final clip = letter.audio;
      if (clip != null) {
        if (!clip.isEncrypted) {
          final bytes = await readAudio(letter);
          if (bytes == null) return letter;
          return await _sealVoice(letter, bytes, local) ?? letter;
        }
        if (clip.keyId == local.keyId && !_sameWrap(clip.wrap, local.wrap)) {
          return letter.copyWith(
            audio: VoiceClip(
              durationMs: clip.durationMs,
              keyId: clip.keyId,
              wrap: local.wrap,
            ),
          );
        }
        return letter;
      }
      final sealed = letter.sealed;
      if (sealed == null) return await _sealLetter(letter, local) ?? letter;
      if (sealed.keyId == local.keyId && !_sameWrap(sealed.wrap, local.wrap)) {
        return _withSealed(
          letter,
          SealedPayload(
            keyId: sealed.keyId,
            data: sealed.data,
            wrap: local.wrap,
          ),
        );
      }
      return letter;
    } catch (_) {
      return letter;
    }
  }

  bool _sameWrap(NoteKeyWrap? a, NoteKeyWrap? b) =>
      a != null &&
      b != null &&
      a.derivationId == b.derivationId &&
      b64(a.wrapped) == b64(b.wrapped);

  FutureLetter _withSealed(FutureLetter letter, SealedPayload sealed) =>
      FutureLetter(
        id: letter.id,
        text: letter.text,
        createdAt: letter.createdAt,
        sealed: sealed,
        audio: letter.audio,
      );

  /// The PIN was removed: bring every note back to plain storage, then drop
  /// the key. If any note on this phone's key cannot be opened, the key is
  /// kept (and nothing is lost): [stillEncrypted] says so.
  Future<({List<FutureLetter> letters, bool stillEncrypted})> deactivate(
    List<FutureLetter> letters,
  ) async {
    final local = await vault.localKey();
    if (local == null) return (letters: letters, stillEncrypted: false);
    final out = <FutureLetter>[];
    var allOpen = true;
    for (final letter in letters) {
      final opened = await _toPlain(letter);
      if (opened == null) {
        out.add(letter);
        if (_usesKey(letter, local.keyId)) allOpen = false;
      } else {
        out.add(opened);
      }
    }
    return (letters: out, stillEncrypted: !allOpen);
  }

  /// After [deactivate] was saved: forget the key.
  Future<void> dropKey() => vault.disable();

  bool _usesKey(FutureLetter l, String kid) =>
      l.sealed?.keyId == kid || l.audio?.keyId == kid;

  Future<FutureLetter?> _toPlain(FutureLetter letter) async {
    final clip = letter.audio;
    if (clip != null) {
      if (!clip.isEncrypted) return letter;
      final bytes = await readAudio(letter);
      if (bytes == null) return null;
      await voice.write(letter.id, bytes, encrypted: false);
      _queueOrphans(letter.id);
      return letter.copyWith(audio: VoiceClip(durationMs: clip.durationMs));
    }
    if (letter.sealed == null) return letter;
    final text = await readText(letter);
    if (text == null) return null;
    return FutureLetter(
      id: letter.id,
      text: FutureLetter.validateText(text),
      createdAt: letter.createdAt,
    );
  }

  /// Opens locked notes with the PIN they were sealed under (an old PIN, a
  /// backup's PIN). Opened notes are re-sealed under this phone's key, or
  /// kept plain when no PIN is set here.
  Future<NoteUnlockResult> unlock(
    List<FutureLetter> letters,
    String pin,
  ) async {
    final lockedIds = <String>{};
    final wraps = <String, NoteKeyWrap>{};
    for (final letter in letters) {
      if (!await isLocked(letter)) continue;
      lockedIds.add(letter.id);
      final kid = letter.sealed?.keyId ?? letter.audio?.keyId;
      final wrap = letter.sealed?.wrap ?? letter.audio?.wrap;
      if (kid != null && wrap != null) wraps.putIfAbsent(kid, () => wrap);
    }
    var any = false;
    for (final entry in wraps.entries) {
      final key = await unwrapNoteKey(entry.value, pin);
      if (key != null) {
        vault.remember(entry.key, key);
        any = true;
      }
    }
    if (!any) {
      return NoteUnlockResult(
        letters: letters,
        opened: 0,
        stillLocked: lockedIds.length,
        wrongPin: lockedIds.isNotEmpty,
      );
    }
    final local = await vault.localKey();
    final out = <FutureLetter>[];
    var opened = 0;
    for (final letter in letters) {
      if (!lockedIds.contains(letter.id)) {
        out.add(letter);
        continue;
      }
      final plain = await _toPlain(letter);
      if (plain == null) {
        out.add(letter);
        continue;
      }
      opened++;
      out.add(local == null ? plain : await _syncOne(plain, local));
    }
    return NoteUnlockResult(
      letters: out,
      opened: opened,
      stillLocked: lockedIds.length - opened,
      wrongPin: false,
    );
  }

  // --- deleting -----------------------------------------------------------

  void _queueOrphans(String id) {
    _maybeOrphaned
      ..add((id, false))
      ..add((id, true));
  }

  /// Notes about to disappear: queue their files for cleanup.
  void forget(Iterable<FutureLetter> removed) {
    for (final l in removed) {
      if (l.isVoice) _queueOrphans(l.id);
    }
  }

  /// Deletes queued files that no saved note refers to any more. Call after
  /// the state that stopped referring to them has been saved.
  Future<void> flushOrphans(List<FutureLetter> current) async {
    final pending = List.of(_maybeOrphaned);
    _maybeOrphaned.clear();
    for (final (id, encrypted) in pending) {
      final used = current.any(
        (l) =>
            l.id == id && l.audio != null && l.audio!.isEncrypted == encrypted,
      );
      if (!used) await voice.delete(id, encrypted: encrypted);
    }
  }

  // --- internals ----------------------------------------------------------

  Future<FutureLetter?> _sealLetter(
    FutureLetter letter,
    LocalNoteKey local,
  ) async {
    if (letter.sealed != null || letter.isVoice) return letter;
    try {
      final sealed = await sealBytes(
        utf8.encode(letter.text),
        keyId: local.keyId,
        key: local.key,
        wrap: local.wrap,
        aad: noteAad(letter.id),
      );
      return FutureLetter(
        id: letter.id,
        text: FutureLetter.sealedPlaceholder,
        createdAt: letter.createdAt,
        sealed: sealed,
      );
    } catch (_) {
      return null;
    }
  }

  Future<FutureLetter?> _sealVoice(
    FutureLetter letter,
    Uint8List bytes,
    LocalNoteKey local,
  ) async {
    try {
      final sealed = await sealBytes(
        bytes,
        keyId: local.keyId,
        key: local.key,
        wrap: null,
        aad: voiceAad(letter.id),
      );
      await voice.write(letter.id, sealed.data, encrypted: true);
      _queueOrphans(letter.id);
      return letter.copyWith(
        audio: VoiceClip(
          durationMs: letter.audio!.durationMs,
          keyId: local.keyId,
          wrap: local.wrap,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
