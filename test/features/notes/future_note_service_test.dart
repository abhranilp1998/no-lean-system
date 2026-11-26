import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/letters/domain/future_letter.dart';

import '../../support/note_fakes.dart';

void main() {
  final at = DateTime(2026, 10, 10, 18);
  final audio = Uint8List.fromList(List.generate(200, (i) => i % 251));

  test('no PIN: notes are plain, exactly as before', () async {
    final phone = FakePhone();
    final note = await phone.notes.createText('Hold on.', at);
    expect(note.sealed, isNull);
    expect(note.text, 'Hold on.');
    expect(await phone.notes.readText(note), 'Hold on.');
    final voice = await phone.notes.createVoice(
      audio,
      const Duration(seconds: 12),
      at,
    );
    expect(voice.audio!.isEncrypted, isFalse);
    expect(await phone.notes.readAudio(voice), audio);
  });

  test(
    'PIN set: new notes are sealed and the file holds no plain text',
    () async {
      final phone = FakePhone();
      await phone.notes.activate('2468', const []);
      final note = await phone.notes.createText('Hold on, secret words.', at);
      expect(note.sealed, isNotNull);
      expect(note.text, FutureLetter.sealedPlaceholder);
      expect(jsonEncode(note.toJson()), isNot(contains('secret words')));
      expect(await phone.notes.readText(note), 'Hold on, secret words.');

      final voice = await phone.notes.createVoice(
        audio,
        const Duration(seconds: 30),
        at,
      );
      expect(voice.audio!.isEncrypted, isTrue);
      expect(phone.voice.files.keys.single, endsWith('.nlv'));
      expect(phone.voice.files.values.single, isNot(audio));
      expect(await phone.notes.readAudio(voice), audio);
    },
  );

  test('recordings longer than 60 s are recorded as 60 s', () async {
    final phone = FakePhone();
    final v = await phone.notes.createVoice(
      audio,
      const Duration(seconds: 90),
      at,
    );
    expect(v.audio!.durationMs, 60000);
  });

  test('turning a PIN on seals existing plain notes and voice files', () async {
    final phone = FakePhone();
    final text = await phone.notes.createText('Old note', at);
    final voice = await phone.notes.createVoice(
      audio,
      const Duration(seconds: 5),
      at,
    );
    final sealed = await phone.notes.activate('2468', [text, voice]);
    expect(sealed[0].sealed, isNotNull);
    expect(sealed[1].audio!.isEncrypted, isTrue);
    await phone.notes.flushOrphans(sealed);
    expect(phone.voice.files.keys.single, endsWith('.nlv'));
    expect(await phone.notes.readText(sealed[0]), 'Old note');
    expect(await phone.notes.readAudio(sealed[1]), audio);
  });

  test('changing the PIN re-wraps: nothing re-encrypted, old PIN no longer '
      'opens new wraps, new PIN does', () async {
    final phone = FakePhone();
    var notes = await phone.notes.activate('1111', const []);
    final first = await phone.notes.createText('Keep going', at);
    notes = [first];
    final oldData = first.sealed!.data;
    notes = await phone.notes.activate('2222', notes);
    expect(b64Equal(notes.single.sealed!.data, oldData), isTrue);
    final other = FakePhone(); // a restore on a new phone
    final r1 = await other.notes.unlock(notes, '1111');
    expect(r1.wrongPin, isTrue);
    final r2 = await other.notes.unlock(notes, '2222');
    expect(r2.opened, 1);
    expect(r2.letters.single.text, 'Keep going'); // no PIN there: plain
  });

  test(
    'removing the PIN returns every note to plain, then drops the key',
    () async {
      final phone = FakePhone();
      await phone.notes.activate('2468', const []);
      final text = await phone.notes.createText('Stay', at);
      final voice = await phone.notes.createVoice(
        audio,
        const Duration(seconds: 5),
        at,
      );
      final plain = await phone.notes.deactivate([text, voice]);
      expect(plain.stillEncrypted, isFalse);
      expect(plain.letters[0].sealed, isNull);
      expect(plain.letters[0].text, 'Stay');
      expect(plain.letters[1].audio!.isEncrypted, isFalse);
      await phone.notes.dropKey();
      await phone.notes.flushOrphans(plain.letters);
      expect(await phone.notes.encrypting, isFalse);
      expect(await phone.notes.readAudio(plain.letters[1]), audio);
      expect(phone.voice.files.keys.single, endsWith('.m4a'));
    },
  );

  test('a note that cannot be opened is kept, and the key with it', () async {
    final phone = FakePhone();
    await phone.notes.activate('2468', const []);
    final good = await phone.notes.createText('fine', at);
    final damaged = FutureLetter(
      id: '${good.id}x',
      text: FutureLetter.sealedPlaceholder,
      createdAt: at,
      sealed: good.sealed, // wrong note id => fails to open
    );
    final r = await phone.notes.deactivate([good, damaged]);
    expect(r.stillEncrypted, isTrue);
    expect(r.letters[0].text, 'fine');
    expect(r.letters[1].sealed, isNotNull);
  });

  test(
    'lost secure storage: notes show as locked, the PIN unlocks them',
    () async {
      final phone = FakePhone();
      await phone.notes.activate('2468', const []);
      final note = await phone.notes.createText('Remember why', at);
      final voice = await phone.notes.createVoice(
        audio,
        const Duration(seconds: 5),
        at,
      );

      // Same app data, fresh Keystore (reinstall / restored files).
      final reinstalled = FakePhone();
      reinstalled.voice.files.addAll(phone.voice.files);
      expect(await reinstalled.notes.isLocked(note), isTrue);
      expect(await reinstalled.notes.readText(note), isNull);
      expect(await reinstalled.notes.readAudio(voice), isNull);

      final wrong = await reinstalled.notes.unlock([note, voice], '0000');
      expect(wrong.wrongPin, isTrue);
      expect(wrong.stillLocked, 2);

      final ok = await reinstalled.notes.unlock([note, voice], '2468');
      expect(ok.opened, 2);
      expect(ok.stillLocked, 0);
      expect(await reinstalled.notes.readText(ok.letters[0]), 'Remember why');
      expect(await reinstalled.notes.readAudio(ok.letters[1]), audio);
    },
  );

  test(
    'unlocking on a phone that has its own PIN re-seals under its key',
    () async {
      final a = FakePhone();
      await a.notes.activate('1357', const []);
      final note = await a.notes.createText('From phone A', at);

      final b = FakePhone();
      await b.notes.activate('9999', const []);
      expect(await b.notes.isLocked(note), isTrue);
      final r = await b.notes.unlock([note], '1357');
      expect(r.opened, 1);
      final moved = r.letters.single;
      expect(moved.sealed!.keyId, isNot(note.sealed!.keyId));
      b.notes.vault.forgetSession();
      expect(await b.notes.readText(moved), 'From phone A');
    },
  );

  test(
    'secure storage failing: nothing is encrypted, nothing is lost',
    () async {
      final phone = FakePhone();
      phone.keys.failWrites = true;
      final text = await phone.notes.createText('plain stays', at);
      final out = await phone.notes.activate('2468', [text]);
      expect(out.single.sealed, isNull);
      expect(await phone.notes.encrypting, isFalse);
      expect(await phone.notes.readText(out.single), 'plain stays');
    },
  );

  test('deleting a voice note removes its files', () async {
    final phone = FakePhone();
    await phone.notes.activate('2468', const []);
    final v = await phone.notes.createVoice(
      audio,
      const Duration(seconds: 3),
      at,
    );
    expect(phone.voice.files, isNotEmpty);
    phone.notes.forget([v]);
    await phone.notes.flushOrphans(const []);
    expect(phone.voice.files, isEmpty);
  });
}

bool b64Equal(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable.generate(a.length).every((i) => a[i] == b[i]);
