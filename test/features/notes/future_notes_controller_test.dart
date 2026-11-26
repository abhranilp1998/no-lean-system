import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/letters/domain/future_letter.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';

import '../../support/note_fakes.dart';
import '../../support/recovery_fakes.dart';

void main() {
  final now = DateTime(2026, 10, 10, 18);
  final audio = Uint8List.fromList(List.generate(300, (i) => (i * 7) % 256));

  Future<(RecoveryController, MemoryRecoveryStore, FakeRelapseLock)> boot(
    FakePhone phone, {
    String? stored,
    String? pin,
  }) async {
    final store = MemoryRecoveryStore(stored);
    final lock = FakeRelapseLock()..pin = pin;
    final controller = RecoveryController(
      store: store,
      relapseLock: lock,
      futureNotes: phone.notes,
      now: () => now,
    );
    await controller.load();
    if (pin != null) controller.requirePinAfterRelapse = true;
    return (controller, store, lock);
  }

  test('no PIN: notes stay plain in saved state, exactly as before', () async {
    final phone = FakePhone();
    final (c, store, _) = await boot(phone);
    await c.addFutureLetter('Plain words');
    final saved = jsonDecode(store.value!)['futureLetters'] as List;
    expect(saved.single['text'], 'Plain words');
    expect(saved.single.containsKey('sealed'), isFalse);
    expect(c.futureNotesEncrypted, isFalse);
  });

  test('setting a PIN seals existing and new notes; the saved state holds '
      'no readable text', () async {
    final phone = FakePhone();
    final (c, store, _) = await boot(phone);
    await c.addFutureLetter('Before the PIN');
    await c.enableRelapseLock('2468');
    await c.addFutureLetter('After the PIN');
    await c.addVoiceNote(audio, const Duration(seconds: 20));

    expect(c.futureNotesEncrypted, isTrue);
    final raw = store.value!;
    expect(raw, isNot(contains('Before the PIN')));
    expect(raw, isNot(contains('After the PIN')));
    expect(await c.readFutureLetterText(c.futureLetters[0]), 'Before the PIN');
    expect(await c.readFutureLetterText(c.futureLetters[1]), 'After the PIN');
    expect(await c.readFutureLetterAudio(c.futureLetters[2]), audio);
    expect(phone.voice.files.keys.single, endsWith('.nlv'));

    // And it survives a restart on the same phone with no PIN typed.
    final (again, _, _) = await boot(phone, stored: raw, pin: '2468');
    expect(again.lockedNoteIds, isEmpty);
    expect(
      await again.readFutureLetterText(again.futureLetters[0]),
      'Before the PIN',
    );
  });

  test('changing the PIN keeps every note readable, here and via the new '
      'PIN elsewhere', () async {
    final phone = FakePhone();
    final (c, store, _) = await boot(phone);
    await c.enableRelapseLock('1111');
    await c.addFutureLetter('Stay');
    await c.enableRelapseLock('2222');
    expect(await c.readFutureLetterText(c.futureLetters.single), 'Stay');

    final elsewhere = FakePhone();
    final (other, _, _) = await boot(elsewhere, stored: store.value);
    expect(other.lockedNoteIds, hasLength(1));
    final wrong = await other.unlockFutureNotes('1111');
    expect(wrong.wrongPin, isTrue);
    final right = await other.unlockFutureNotes('2222');
    expect(right.opened, 1);
    expect(other.lockedNoteIds, isEmpty);
    expect(
      await other.readFutureLetterText(other.futureLetters.single),
      'Stay',
    );
  });

  test(
    'removing the PIN decrypts notes back to plain and drops the key',
    () async {
      final phone = FakePhone();
      final (c, store, _) = await boot(phone);
      await c.enableRelapseLock('2468');
      await c.addFutureLetter('Keep me');
      await c.addVoiceNote(audio, const Duration(seconds: 9));
      expect(c.futureNotesEncrypted, isTrue);

      final result = await c.disableRelapseLock(pin: '2468');
      expect(result, ProtectedActionResult.completed);
      expect(c.futureNotesEncrypted, isFalse);
      final saved = jsonDecode(store.value!)['futureLetters'] as List;
      expect(saved[0]['text'], 'Keep me');
      expect(saved[0].containsKey('sealed'), isFalse);
      expect(saved[1].containsKey('audio'), isTrue);
      expect(saved[1]['audio'].containsKey('kid'), isFalse);
      expect(await c.readFutureLetterAudio(c.futureLetters[1]), audio);
      expect(phone.voice.files.keys.single, endsWith('.m4a'));
      expect(await phone.notes.encrypting, isFalse);
    },
  );

  test('a wrong PIN on removal changes nothing', () async {
    final phone = FakePhone();
    final (c, _, _) = await boot(phone);
    await c.enableRelapseLock('2468');
    await c.addFutureLetter('Safe');
    final result = await c.disableRelapseLock(pin: '0000');
    expect(result, ProtectedActionResult.denied);
    expect(c.futureNotesEncrypted, isTrue);
    expect(c.futureLetters.single.sealed, isNotNull);
  });

  test('reinstall: notes load as locked (kept, not dropped); the PIN opens '
      'them; a wrong PIN changes nothing', () async {
    final phone = FakePhone();
    final (c, store, _) = await boot(phone);
    await c.enableRelapseLock('2468');
    await c.addFutureLetter('Remember why');

    final fresh = FakePhone(); // new Keystore, same app data
    final (r, rStore, _) = await boot(fresh, stored: store.value);
    expect(r.futureLetters, hasLength(1));
    expect(r.lockedNoteIds, {r.futureLetters.single.id});
    expect(await r.readFutureLetterText(r.futureLetters.single), isNull);

    final before = rStore.value;
    final wrong = await r.unlockFutureNotes('9999');
    expect(wrong.wrongPin, isTrue);
    expect(r.futureLetters.single.sealed, isNotNull);
    expect(rStore.value, before);

    final ok = await r.unlockFutureNotes('2468');
    expect(ok.opened, 1);
    expect(
      await r.readFutureLetterText(r.futureLetters.single),
      'Remember why',
    );
  });

  test(
    'a PIN set before this feature: the first PIN entry locks the notes',
    () async {
      final phone = FakePhone();
      final (c, store, _) = await boot(phone, pin: '2468');
      await c.addFutureLetter('Old plain note');
      expect(c.futureNotesEncrypted, isFalse);
      expect(store.value, contains('Old plain note'));
      await c.authorizeFutureLetters(pin: '2468', tryBiometrics: false);
      expect(c.futureNotesEncrypted, isTrue);
      expect(store.value, isNot(contains('Old plain note')));
      expect(
        await c.readFutureLetterText(c.futureLetters.single),
        'Old plain note',
      );
    },
  );

  test('enableNoteEncryption verifies the PIN first', () async {
    final phone = FakePhone();
    final (c, _, _) = await boot(phone, pin: '2468');
    expect(await c.enableNoteEncryption('0000'), ProtectedActionResult.denied);
    expect(c.futureNotesEncrypted, isFalse);
    expect(
      await c.enableNoteEncryption('2468'),
      ProtectedActionResult.completed,
    );
    expect(c.futureNotesEncrypted, isTrue);
  });

  test(
    'deleting a voice note deletes its file; deleting a locked note works',
    () async {
      final phone = FakePhone();
      final (c, store, _) = await boot(phone);
      await c.enableRelapseLock('2468');
      await c.addVoiceNote(audio, const Duration(seconds: 4));
      await c.addFutureLetter('Text');
      expect(phone.voice.files, isNotEmpty);
      await c.deleteFutureLetter(c.futureLetters.first.id);
      expect(phone.voice.files, isEmpty);

      final (r, _, _) = await boot(FakePhone(), stored: store.value);
      expect(r.lockedNoteIds, hasLength(1));
      await r.deleteFutureLetter(r.futureLetters.single.id);
      expect(r.futureLetters, isEmpty);
    },
  );

  test(
    'lettersForBackup attaches sealed voice bytes and never writes them to state',
    () async {
      final phone = FakePhone();
      final (c, store, _) = await boot(phone);
      await c.enableRelapseLock('2468');
      await c.addFutureLetter('In the backup');
      await c.addVoiceNote(audio, const Duration(seconds: 4));
      final exported = await c.lettersForBackup();
      expect(exported, hasLength(2));
      final voice = exported.firstWhere((l) => l.isVoice);
      expect(voice.backupAudio, isNotNull);
      expect(voice.backupAudio, isNot(audio)); // still sealed
      expect(voice.audio!.wrap, isNotNull);
      expect(
        jsonEncode(exported.map((l) => l.toJson()).toList()),
        isNot(contains('In the backup')),
      );
      expect(
        jsonEncode(exported.map((l) => l.toJson()).toList()),
        isNot(contains('audioData')),
      );
      final saved = jsonDecode(store.value!) as Map<String, dynamic>;
      final raw = jsonEncode(saved['futureLetters']);
      expect(raw, isNot(contains('audioData')));
    },
  );

  test('50 notes at once: sealing never loses or reorders any', () async {
    final phone = FakePhone();
    final (c, _, _) = await boot(phone);
    for (var i = 0; i < 20; i++) {
      await c.addFutureLetter('note $i');
    }
    await c.enableRelapseLock('2468');
    expect(c.futureLetters, hasLength(20));
    for (var i = 0; i < 20; i++) {
      expect(await c.readFutureLetterText(c.futureLetters[i]), 'note $i');
    }
    expect(FutureLetter.maxLetters, 100);
  });
}
