import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

import '../../../support/recovery_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(RecoveryController, MemoryRecoveryStore)> loaded({
    String? stored,
  }) async {
    final store = MemoryRecoveryStore(stored);
    final controller = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
    );
    await controller.load();
    return (controller, store);
  }

  String v9State([Map<String, Object?> extra = const {}]) => jsonEncode({
    'stateVersion': 9,
    'events': [
      RecoveryEvent.create(
        type: RecoveryEventType.recoveryStart,
        timestamp: DateTime(2026, 9, 1),
      ).toJson(),
    ],
    'zones': [],
    ...extra,
  });

  test(
    'v9 migrates to v10 with street tiles on and the v9 copy kept',
    () async {
      final (controller, store) = await loaded(stored: v9State());
      expect(controller.streetTiles, isTrue);
      final saved = jsonDecode(store.value!) as Map;
      expect(saved['stateVersion'], 10);
      expect(saved['streetTiles'], isTrue);
      expect(store.copies.single, contains('"stateVersion":9'));
    },
  );

  test('street tiles toggle persists and needs no authentication', () async {
    final (controller, store) = await loaded();
    await controller.enableRelapseLock('2468');
    await controller.setStreetTiles(false);
    expect(controller.streetTiles, isFalse);

    final reloaded = RecoveryController(
      store: store,
      relapseLock: FakeRelapseLock(),
    );
    await reloaded.load();
    expect(reloaded.streetTiles, isFalse);
  });

  test('a malformed value falls back to the default', () async {
    final (controller, _) = await loaded(
      stored: v9State({'stateVersion': 10, 'streetTiles': 'nope'}),
    );
    expect(controller.streetTiles, isTrue);
  });

  test('imported preferences never change network privacy', () async {
    final (controller, _) = await loaded();
    await controller.setStreetTiles(false);
    await controller.mergeImportedEvents(
      const [],
      preferences: {'streetTiles': true},
      restorePreferences: true,
    );
    expect(controller.streetTiles, isFalse);
  });

  test('states from a newer app version are refused unchanged', () async {
    final newer = v9State({'stateVersion': 11});
    final (controller, store) = await loaded(stored: newer);
    expect(controller.loadStatus, RecoveryLoadStatus.incompatible);
    expect(store.value, newer);
  });
}
