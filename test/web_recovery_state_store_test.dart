@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';
import 'package:no_lean/features/recovery/services/recovery_state_store_web.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String databaseName;
  late MemoryRecoveryStore legacy;

  BrowserRecoveryStateStore openStore() =>
      BrowserRecoveryStateStore(databaseName: databaseName, legacy: legacy);

  setUp(() {
    databaseName = 'no_lean_test_${const Uuid().v4()}';
    legacy = MemoryRecoveryStore();
    SharedPreferences.setMockInitialValues({});
  });

  test('production web provider opens history without native files', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final recovery = container.read(recoveryProvider);
    await recovery.load();
    expect(recovery.loadStatus, RecoveryLoadStatus.ready);
    expect(recovery.events, isNotEmpty);
  });

  test(
    'cravings and settings survive a new controller and connection',
    () async {
      final recovery = RecoveryController(
        store: openStore(),
        relapseLock: FakeRelapseLock(),
      );
      addTearDown(recovery.dispose);
      await recovery.load();
      await recovery.recordCraving(
        CravingEntry(
          intensity: 7,
          trigger: 'Stress',
          note: 'Browser round trip',
          createdAt: DateTime(2025, 4, 2, 18),
        ),
      );
      await recovery.updateDailySpend(125);
      final reopened = RecoveryController(
        store: openStore(),
        relapseLock: FakeRelapseLock(),
      );
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.loadStatus, RecoveryLoadStatus.ready);
      expect(reopened.cravings.single.note, 'Browser round trip');
      expect(reopened.dailySpend, 125);
      expect(
        reopened.events.map((event) => event.toJson()).toList(),
        recovery.events.map((event) => event.toJson()).toList(),
      );
    },
  );

  test('migration retains its source and preserved copies', () async {
    final source = jsonEncode({
      'stateVersion': 5,
      'lastDose': '2025-04-02T18:00:00.000',
      'dailySpend': 125,
      'cleanDays': {'2025-04-02': false},
    });
    legacy.value = source;
    legacy.copies.add('a retained older copy');
    final recovery = RecoveryController(
      store: openStore(),
      relapseLock: FakeRelapseLock(),
    );
    addTearDown(recovery.dispose);
    await recovery.load();
    expect(recovery.loadStatus, RecoveryLoadStatus.ready);
    expect(recovery.cleanDays['2025-04-02'], isFalse);
    expect(legacy.value, source);
    expect(
      await openStore().recoveryCopies(),
      containsAll([source, 'a retained older copy']),
    );
  });

  test('each save retains the preceding committed history', () async {
    final store = openStore();
    await store.write('first');
    await store.preserve('migration source');
    await store.write('second');
    await store.write('third');
    expect(await openStore().read(), 'third');
    expect(
      await openStore().recoveryCopies(),
      containsAll(['second', 'migration source']),
    );
  });

  for (final source in [
    'broken JSON',
    jsonEncode({'stateVersion': 999, 'events': []}),
  ]) {
    test('invalid current history is not replaced: $source', () async {
      await openStore().write(source);
      final recovery = RecoveryController(
        store: openStore(),
        relapseLock: FakeRelapseLock(),
      );
      addTearDown(recovery.dispose);
      await recovery.load();
      expect(recovery.isLoaded, isFalse);
      await expectLater(recovery.pledge(), throwsStateError);
      expect(await openStore().read(), source);
    });
  }

  test(
    'stale tab write aborts without overwriting either committed copy',
    () async {
      final firstTab = openStore();
      final otherTab = openStore();
      await firstTab.write('initial');
      await otherTab.read();
      await firstTab.write('newer history');
      await expectLater(otherTab.write('stale history'), throwsStateError);
      expect(await openStore().read(), 'newer history');
      expect(await openStore().recoveryCopies(), ['initial']);
      await otherTab.read();
      await otherTab.write('saved after reload');
      expect(await openStore().read(), 'saved after reload');
    },
  );

  test(
    'legacy PIN is removed from current and preserved browser copies',
    () async {
      final store = openStore();
      final source = jsonEncode({'stateVersion': 3, 'pin': '1234'});
      await store.write(source);
      await store.preserve(source);
      await store.removeLegacyPin();
      expect(jsonDecode((await store.read())!), isNot(contains('pin')));
      for (final copy in await store.recoveryCopies()) {
        expect(jsonDecode(copy), isNot(contains('pin')));
      }
      await store.write('next history');
      expect(await store.read(), 'next history');
    },
  );
}
