import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/letters/domain/future_letter.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../support/note_fakes.dart';
import '../support/recovery_fakes.dart';

/// Rule: always backwards compatible. Encrypted and voice notes add only
/// optional keys: no state or backup version bump.
void main() {
  final now = DateTime(2026, 11, 26, 20);

  Map<String, dynamic> oldBackup(int version, {bool withLetters = true}) => {
    'version': version,
    'exportedAt': '2026-11-20T10:00:00.000',
    'events': [
      {
        'id': 'start',
        'type': 'recoveryStart',
        'timestamp': '2026-10-01T09:00:00.000',
        'metadata': {'source': 'onboarding'},
      },
    ],
    'zones': <Object>[],
    'preferences': {'dailySpend': 250},
    if (withLetters)
      'futureLetters': [
        {
          'id': 'old-1',
          'text': 'You got through worse.',
          'createdAt': '2026-10-05T20:00:00.000',
          'someFutureKey': 7,
        },
      ],
  };

  Future<RecoveryController> blank(FakePhone phone, {String? stored}) async {
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

  test('no version bump', () {
    // Release 1.8.0-beta.1 carries state v18 / backup v13 from other PRs;
    // this feature adds no bump of its own on top.
    expect(RecoveryController.stateVersion, 18);
    expect(BackupService.currentBackupVersion, 13);
  });

  for (final v in [8, 9, 11, 12]) {
    test(
      'backup format $v imports; plain notes stay plain and readable',
      () async {
        final preview = BackupService().validateBackupJson(
          jsonEncode(oldBackup(v, withLetters: v >= 9)),
        );
        final c = await blank(FakePhone());
        await c.mergeImportedEvents(
          preview.events,
          importedLetters: preview.letters,
          preferences: preview.preferences,
        );
        if (v >= 9) {
          expect(c.futureLetters.single.text, 'You got through worse.');
          expect(c.futureLetters.single.sealed, isNull);
          expect(
            await c.readFutureLetterText(c.futureLetters.single),
            'You got through worse.',
          );
        } else {
          expect(c.futureLetters, isEmpty);
        }
      },
    );
  }

  test('an old backup imported onto a phone with a PIN: notes get sealed, '
      'nothing lost', () async {
    final phone = FakePhone();
    final c = await blank(phone);
    await c.enableRelapseLock('2468');
    final preview = BackupService().validateBackupJson(
      jsonEncode(oldBackup(12)),
    );
    await c.mergeImportedEvents(
      preview.events,
      importedLetters: preview.letters,
      pin: '2468',
      tryBiometrics: false,
    );
    await c.secureFutureNotes();
    expect(c.futureLetters.single.sealed, isNotNull);
    expect(
      await c.readFutureLetterText(c.futureLetters.single),
      'You got through worse.',
    );
  });

  test(
    'an old saved state (plain notes, no new keys) loads and re-saves',
    () async {
      final stored = jsonEncode({
        'stateVersion': 17,
        'events': <Object>[],
        'futureLetters': [
          {
            'id': 'a',
            'text': 'Plain one',
            'createdAt': '2026-10-05T20:00:00.000',
          },
        ],
      });
      final store = MemoryRecoveryStore(stored);
      final c = RecoveryController(
        store: store,
        relapseLock: FakeRelapseLock(),
        now: () => now,
      );
      await c.load();
      expect(c.futureLetters.single.text, 'Plain one');
      expect(c.lockedNoteIds, isEmpty);
      await c.addFutureLetter('Another');
      final saved = jsonDecode(store.value!)['futureLetters'] as List;
      expect(saved.first, {
        'id': 'a',
        'text': 'Plain one',
        'createdAt': '2026-10-05T20:00:00.000',
      });
    },
  );

  /// What every earlier build did with a note: require id, text, createdAt.
  FutureLetter legacyParse(Map<String, dynamic> json) {
    final id = json['id'];
    final text = json['text'];
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (id is! String || id.isEmpty || text is! String || createdAt == null) {
      throw const FormatException('bad');
    }
    if (text.trim().isEmpty || text.trim().length > 4000) {
      throw const FormatException('bad');
    }
    return FutureLetter(id: id, text: text.trim(), createdAt: createdAt);
  }

  test('sealed and voice notes still parse in an older build (placeholder '
      'text, extra keys ignored)', () async {
    final phone = FakePhone();
    final c = await blank(phone);
    await c.enableRelapseLock('2468');
    await c.addFutureLetter('secret');
    await c.addVoiceNote(
      (await phone.notes.createText('x', now)).sealed!.data,
      const Duration(seconds: 3),
    );
    for (final l in c.futureLetters) {
      final json = jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>;
      final old = legacyParse(json);
      expect(old.text, isNot('secret'));
      expect(old.text, isNotEmpty);
    }
  });

  test(
    'a sealed note exported and re-imported keeps its seal, unchanged',
    () async {
      final phone = FakePhone();
      final c = await blank(phone);
      await c.enableRelapseLock('2468');
      await c.addFutureLetter('sealed text');
      final payload = BackupService().buildBackupPayload(
        c.events,
        preferences: c.portablePreferences,
        letters: c.exportableLetters,
      );
      final preview = BackupService().validateBackupJson(jsonEncode(payload));
      expect(
        jsonEncode(preview.letters.single.toJson()),
        jsonEncode(c.futureLetters.single.toJson()),
      );
      expect(jsonEncode(payload), isNot(contains('sealed text')));
    },
  );

  test('a damaged seal never blocks loading and the note is kept', () {
    final l = FutureLetter.fromJson({
      'id': 'z',
      'text': FutureLetter.sealedPlaceholder,
      'createdAt': '2026-10-05T20:00:00.000',
      'sealed': {'v': 99, 'junk': true},
      'audio': 'nope',
    });
    expect(l.sealed, isNull);
    expect(l.audio, isNull);
    expect(l.text, FutureLetter.sealedPlaceholder);
  });

  test('audioData is ignored by an older parser; a format-12 backup without '
      'it still imports', () {
    final modern = {
      'id': 'v1',
      'text': FutureLetter.voicePlaceholder,
      'createdAt': '2026-10-05T20:00:00.000',
      'audio': {
        'ms': 4000,
        'kid': 'k',
        'w': {'s': 'YQ', 'i': 1000, 'k': 'YQ'},
      },
      'audioData': 'YWJjZA',
    };
    final old = legacyParse(modern);
    expect(old.id, 'v1');
    expect(old.backupAudio, isNull);
    expect(old.audio, isNull);

    final preview = BackupService().validateBackupJson(
      jsonEncode(oldBackup(12)),
    );
    expect(preview.letters.single.backupAudio, isNull);
    expect(preview.letters.single.text, 'You got through worse.');
  });
}
