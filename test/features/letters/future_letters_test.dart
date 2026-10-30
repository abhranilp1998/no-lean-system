import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/letters/domain/future_letter.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

import '../../support/recovery_fakes.dart';

void main() {
  var now = DateTime(2026, 10, 10, 18);

  Future<(RecoveryController, MemoryRecoveryStore, FakeRelapseLock)> load([
    String? stored,
    String? pin,
  ]) async {
    final store = MemoryRecoveryStore(stored);
    final lock = FakeRelapseLock()..pin = pin;
    final controller = RecoveryController(
      store: store,
      relapseLock: lock,
      now: () => now,
    );
    await controller.load();
    return (controller, store, lock);
  }

  setUp(() => now = DateTime(2026, 10, 10, 18));

  group('domain', () {
    test('rejects empty, oversize and malformed notes', () {
      expect(() => FutureLetter.create('  '), throwsFormatException);
      expect(
        () => FutureLetter.create('x' * (FutureLetter.maxLength + 1)),
        throwsFormatException,
      );
      expect(() => FutureLetter.fromJson({'id': 'a'}), throwsFormatException);
      expect(FutureLetter.decodeList(null), isEmpty);
    });

    test('one note per evening, rotating; before the window it is '
        'still last evening', () {
      const window = RiskWindow.defaultWindow(); // 17:00-21:00
      final evening = DateTime(2026, 10, 10, 18);
      final next = DateTime(2026, 10, 11, 18);
      final morning = DateTime(2026, 10, 11, 9);
      final a = tonightLetterIndex(3, evening, window);
      expect(tonightLetterIndex(3, next, window), (a + 1) % 3);
      expect(tonightLetterIndex(3, morning, window), a);
      expect(tonightLetterIndex(0, evening, window), -1);
    });
  });

  test('state v13 loads with no notes and is saved as v14', () async {
    final (controller, store, _) = await load(
      jsonEncode({'stateVersion': 13, 'events': <Object>[]}),
    );
    expect(RecoveryController.stateVersion, 14);
    expect(controller.futureLetters, isEmpty);
    expect(controller.tonightLetter, isNull);
    await controller.addFutureLetter('You got through worse.');
    final saved = jsonDecode(store.value!) as Map<String, dynamic>;
    expect(saved['stateVersion'], 14);
    expect(
      (saved['futureLetters'] as List).single['text'],
      'You got '
      'through worse.',
    );

    final (reloaded, _, _) = await load(store.value);
    expect(reloaded.futureLetters.single.text, 'You got through worse.');
    expect(reloaded.tonightLetter!.text, 'You got through worse.');
  });

  test('a malformed stored notes list does not block loading', () async {
    final (controller, _, _) = await load(
      jsonEncode({
        'stateVersion': 14,
        'events': <Object>[],
        'futureLetters': 'nope',
      }),
    );
    expect(controller.loadStatus, RecoveryLoadStatus.ready);
    expect(controller.futureLetters, isEmpty);
  });

  test('opening notes needs the PIN when one is set', () async {
    final (open, _, _) = await load();
    expect(
      await open.authorizeFutureLetters(),
      ProtectedActionResult.completed,
    );
    final (locked, _, _) = await load(
      jsonEncode({
        'stateVersion': 14,
        'events': <Object>[],
        'requirePinAfterRelapse': true,
      }),
      '1234',
    );
    expect(
      await locked.authorizeFutureLetters(),
      ProtectedActionResult.authenticationRequired,
    );
    expect(
      await locked.authorizeFutureLetters(pin: '0000', tryBiometrics: false),
      ProtectedActionResult.denied,
    );
    expect(
      await locked.authorizeFutureLetters(pin: '1234', tryBiometrics: false),
      ProtectedActionResult.completed,
    );
  });

  group('backups', () {
    test('format 9 round-trips notes and merges them by ID', () async {
      final (source, _, _) = await load();
      await source.addFutureLetter('one');
      await source.addFutureLetter('two');
      final service = BackupService();
      final json = jsonEncode(
        service.buildBackupPayload(
          source.events,
          preferences: source.portablePreferences,
          zones: source.zones,
          letters: source.futureLetters,
        ),
      );
      final preview = service.validateBackupJson(json);
      expect(preview.letters.map((l) => l.text), ['one', 'two']);

      final (target, _, _) = await load();
      await target.addFutureLetter('mine');
      for (var i = 0; i < 2; i++) {
        await target.mergeImportedEvents(
          preview.events,
          importedLetters: preview.letters,
        );
      }
      expect(target.futureLetters.map((l) => l.text), ['mine', 'one', 'two']);
    });

    test('format 8 backups (no notes) still import', () {
      final preview = BackupService().validateBackupJson(
        jsonEncode({
          'version': 8,
          'events': <Object>[],
          'preferences': <String, Object>{},
        }),
      );
      expect(preview.letters, isEmpty);
    });

    test('a malformed notes list in a backup is refused', () {
      expect(
        () => BackupService().validateBackupJson(
          jsonEncode({
            'version': 9,
            'events': <Object>[],
            'futureLetters': [
              {'id': 'x'},
            ],
          }),
        ),
        throwsFormatException,
      );
    });
  });
}
