import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/letters/domain/future_letter.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../support/note_fakes.dart';
import '../../support/recovery_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 26, 20);

  Future<RecoveryController> boot(FakePhone phone, {String? stored}) async {
    final c = RecoveryController(
      store: MemoryRecoveryStore(stored),
      relapseLock: FakeRelapseLock(),
      futureNotes: phone.notes,
      now: () => now,
      cancelUseCheck: () async {},
      scheduleCravingCheck: (_) async => true,
      cancelCravingCheck: () async {},
    );
    await c.load();
    return c;
  }

  Uint8List tone(int seed, int length) =>
      Uint8List.fromList(List.generate(length, (i) => (seed + i * 13) % 256));

  test('plain and sealed voice notes round-trip through a backup', () async {
    final sourcePhone = FakePhone();
    final source = await boot(sourcePhone);
    final plain = tone(1, 200);
    await source.addVoiceNote(plain, const Duration(seconds: 4));
    await source.enableRelapseLock('2468');
    final sealed = tone(2, 220);
    await source.addVoiceNote(sealed, const Duration(seconds: 6));
    await source.addFutureLetter('A text note');

    final plan = BackupService().planBackup(
      source.events,
      preferences: source.portablePreferences,
      letters: await source.lettersForBackup(),
    );
    expect(plan.includedVoiceCount, 2);
    expect(plan.skippedVoiceCount, 0);
    expect(jsonEncode(plan.payload), isNot(contains('A text note')));
    // State snapshot still has no audioData.
    expect(
      jsonEncode(plan.payload['futureLetters']).contains('audioData'),
      isTrue,
    );

    final preview = BackupService().validateBackupJson(
      jsonEncode(plan.payload),
    );
    expect(
      preview.letters.where((l) => l.isVoice && l.backupAudio != null),
      hasLength(2),
    );

    final destPhone = FakePhone();
    final dest = await boot(destPhone);
    await dest.mergeImportedEvents(
      preview.events,
      importedLetters: preview.letters,
    );
    await dest.importVoiceAudio(preview.letters);
    await dest.secureFutureNotes();

    expect(dest.futureLetters, hasLength(3));
    // Everything was sealed under the source PIN, so on a new phone
    // the notes stay locked until that PIN is entered.
    expect(dest.lockedNoteIds, hasLength(3));
    final unlocked = await dest.unlockFutureNotes('2468');
    expect(unlocked.wrongPin, isFalse);
    expect(unlocked.opened, 3);
    expect(dest.lockedNoteIds, isEmpty);
    FutureLetter voiceOf(int ms) => dest.futureLetters.firstWhere(
      (l) => l.isVoice && l.audio!.durationMs == ms,
    );
    expect(await dest.readFutureLetterAudio(voiceOf(4000)), plain);
    expect(await dest.readFutureLetterAudio(voiceOf(6000)), sealed);
    expect(
      await dest.readFutureLetterText(
        dest.futureLetters.firstWhere((l) => !l.isVoice),
      ),
      'A text note',
    );
  });

  test(
    'sealed voice imported under another key stays locked until the old PIN',
    () async {
      final a = FakePhone();
      final source = await boot(a);
      await source.enableRelapseLock('1357');
      final clip = tone(9, 180);
      await source.addVoiceNote(clip, const Duration(seconds: 8));
      final plan = BackupService().planBackup(
        source.events,
        preferences: source.portablePreferences,
        letters: await source.lettersForBackup(),
      );
      final preview = BackupService().validateBackupJson(
        jsonEncode(plan.payload),
      );

      final b = FakePhone();
      final dest = await boot(b);
      await dest.enableRelapseLock('9999');
      await dest.mergeImportedEvents(
        preview.events,
        importedLetters: preview.letters,
        pin: '9999',
        tryBiometrics: false,
      );
      await dest.importVoiceAudio(preview.letters);
      await dest.secureFutureNotes();

      final note = dest.futureLetters.single;
      expect(dest.lockedNoteIds, {note.id});
      expect(await dest.readFutureLetterAudio(note), isNull);
      // The sealed file itself is on the new phone.
      expect(b.voice.files.keys.single, endsWith('.nlv'));

      final wrong = await dest.unlockFutureNotes('0000');
      expect(wrong.wrongPin, isTrue);
      expect(dest.lockedNoteIds, {note.id});

      final ok = await dest.unlockFutureNotes('1357');
      expect(ok.opened, 1);
      expect(dest.lockedNoteIds, isEmpty);
      expect(await dest.readFutureLetterAudio(dest.futureLetters.single), clip);
    },
  );

  test(
    'a backup without audioData does not wipe an existing local recording',
    () async {
      final phone = FakePhone();
      final c = await boot(phone);
      final mine = tone(3, 150);
      await c.addVoiceNote(mine, const Duration(seconds: 5));
      final local = c.futureLetters.single;

      // An older backup: same note id, metadata only, no audioData — plus a
      // new voice note that also has no file in the backup.
      final other = FutureLetter(
        id: 'from-old-backup',
        text: FutureLetter.voicePlaceholder,
        createdAt: DateTime(2026, 10, 1),
        audio: const VoiceClip(durationMs: 9000),
      );
      final raw = jsonEncode(
        BackupService().buildBackupPayload(
          const [],
          preferences: const {},
          letters: [local, other],
        ),
      );
      expect(raw, isNot(contains('audioData')));
      final preview = BackupService().validateBackupJson(raw);
      expect(preview.letters.every((l) => l.backupAudio == null), isTrue);

      final before = Map.of(phone.voice.files);
      await c.mergeImportedEvents(
        preview.events,
        importedLetters: preview.letters,
      );
      await c.importVoiceAudio(preview.letters);

      expect(
        await c.readFutureLetterAudio(
          c.futureLetters.firstWhere((l) => l.id == local.id),
        ),
        mine,
      );
      expect(phone.voice.files, before); // nothing deleted or overwritten
      expect(
        c.futureLetters.map((l) => l.id),
        containsAll([local.id, other.id]),
      );
      expect(
        await c.readFutureLetterAudio(
          c.futureLetters.firstWhere((l) => l.id == other.id),
        ),
        isNull,
      );
    },
  );

  test(
    'importing audio fills a missing file but never overwrites one',
    () async {
      final phone = FakePhone();
      final c = await boot(phone);
      final original = tone(4, 120);
      await c.addVoiceNote(original, const Duration(seconds: 3));
      final note = c.futureLetters.single;

      final otherBytes = tone(5, 120);
      final incoming = note.copyWith(backupAudio: otherBytes);
      await c.importVoiceAudio([incoming]);
      expect(await c.readFutureLetterAudio(note), original);

      phone.voice.files.clear();
      await c.importVoiceAudio([incoming]);
      expect(await c.readFutureLetterAudio(c.futureLetters.single), otherBytes);
    },
  );

  test(
    'newest voice recordings fit under a tight cap; older ones are skipped',
    () async {
      final older = FutureLetter(
        id: 'old',
        text: FutureLetter.voicePlaceholder,
        createdAt: DateTime(2026, 1, 1),
        audio: const VoiceClip(durationMs: 10000),
        backupAudio: tone(1, 800),
      );
      final newer = FutureLetter(
        id: 'new',
        text: FutureLetter.voicePlaceholder,
        createdAt: DateTime(2026, 11, 1),
        audio: const VoiceClip(durationMs: 20000),
        backupAudio: tone(2, 800),
      );
      final text = FutureLetter(
        id: 'text',
        text: 'Keep me',
        createdAt: DateTime(2026, 6, 1),
      );
      // A cap that can hold the skeleton plus exactly one 800-byte recording.
      final skeleton = BackupService().buildBackupPayload(
        const [],
        preferences: const {'dailySpend': 1},
        letters: [older, newer, text],
      );
      final skeletonSize = utf8.encode(jsonEncode(skeleton)).length;
      final oneAudio =
          utf8
              .encode(
                jsonEncode({
                  ...newer.toJson(),
                  'audioData': base64Url.encode(newer.backupAudio!),
                }),
              )
              .length -
          utf8.encode(jsonEncode(newer.toJson())).length;
      final cap = skeletonSize + oneAudio + 8; // room for one, not two

      final plan = BackupService().planBackup(
        const [],
        preferences: const {'dailySpend': 1},
        letters: [older, newer, text],
        maxBytes: cap,
      );
      expect(plan.includedVoiceIds, ['new']);
      expect(plan.skippedVoiceIds, ['old']);
      expect(plan.voiceNotice, contains('1 voice note included'));
      expect(plan.voiceNotice, contains('1 older recording did not fit'));
      expect(plan.voiceNotice, contains('5 MB'));

      final encoded = jsonEncode(plan.payload);
      expect(utf8.encode(encoded).length, lessThanOrEqualTo(cap));
      expect(encoded, contains('Keep me'));
      final maps = (plan.payload['futureLetters'] as List).cast<Map>();
      expect(maps.map((m) => m['id']), containsAll(['old', 'new', 'text']));
      expect(maps.firstWhere((m) => m['id'] == 'new')['audioData'], isNotNull);
      expect(
        maps.firstWhere((m) => m['id'] == 'old').containsKey('audioData'),
        isFalse,
      );

      // Full 5 MB cap still packs both of these tiny recordings.
      final full = BackupService().planBackup(
        const [],
        preferences: const {},
        letters: [older, newer],
      );
      expect(full.includedVoiceCount, 2);
      expect(full.skippedVoiceCount, 0);
      expect(
        utf8.encode(jsonEncode(full.payload)).length,
        lessThan(BackupService.maxBackupBytes),
      );
    },
  );

  test(
    'a missing file is reported, not packed, and the note metadata stays',
    () {
      final missing = FutureLetter(
        id: 'gone',
        text: FutureLetter.voicePlaceholder,
        createdAt: DateTime(2026, 11, 1),
        audio: const VoiceClip(durationMs: 3000),
      );
      final plan = BackupService().planBackup(
        const [],
        preferences: const {},
        letters: [missing],
      );
      expect(plan.includedVoiceCount, 0);
      expect(plan.missingVoiceIds, ['gone']);
      expect(plan.voiceNotice, contains('had no recording on this phone'));
      final maps = (plan.payload['futureLetters'] as List).cast<Map>();
      expect(maps.single['id'], 'gone');
      expect(maps.single.containsKey('audioData'), isFalse);
    },
  );

  test('junk or oversized audioData is ignored; the note still loads', () {
    final ok = FutureLetter.fromJson({
      'id': 'z',
      'text': FutureLetter.voicePlaceholder,
      'createdAt': '2026-10-05T20:00:00.000',
      'audio': {'ms': 4000},
      'audioData': '!!!not-base64!!!',
    });
    expect(ok.backupAudio, isNull);
    expect(ok.isVoice, isTrue);

    final huge = FutureLetter.fromJson({
      'id': 'h',
      'text': FutureLetter.voicePlaceholder,
      'createdAt': '2026-10-05T20:00:00.000',
      'audio': {'ms': 4000},
      'audioData': base64Url.encode(
        Uint8List(VoiceClip.maxBackupAudioBytes + 1),
      ),
    });
    expect(huge.backupAudio, isNull);
  });
}
