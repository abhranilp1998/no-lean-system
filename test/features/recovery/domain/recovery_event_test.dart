import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

void main() {
  group('RecoveryEvent', () {
    test('create generates unique id and defaults timestamp', () {
      final event1 = RecoveryEvent.create(type: RecoveryEventType.pledge);
      final event2 = RecoveryEvent.create(type: RecoveryEventType.pledge);

      expect(event1.id, isNotEmpty);
      expect(event2.id, isNotEmpty);
      expect(event1.id, isNot(equals(event2.id)));
      
      final diff = DateTime.now().difference(event1.timestamp).abs();
      expect(diff.inSeconds, lessThan(5));
      expect(event1.metadata, isEmpty);
    });

    test('copyWith updates metadata but preserves other fields', () {
      final event = RecoveryEvent.create(
        type: RecoveryEventType.craving,
        timestamp: DateTime(2023, 1, 1),
        metadata: {'note': 'old'},
      );

      final updated = event.copyWith(metadata: {'note': 'new', 'intensity': 5});

      expect(updated.id, event.id);
      expect(updated.type, event.type);
      expect(updated.timestamp, event.timestamp);
      expect(updated.metadata, {'note': 'new', 'intensity': 5});
    });

    test('toJson and fromJson serialize properly', () {
      final event = RecoveryEvent.create(
        type: RecoveryEventType.sosComplete,
        timestamp: DateTime(2023, 1, 1, 12, 0),
        metadata: {'durationSeconds': 60, 'debrief': 'down'},
      );

      final json = event.toJson();
      final restored = RecoveryEvent.fromJson(json);

      expect(restored.id, event.id);
      expect(restored.type, RecoveryEventType.sosComplete);
      expect(restored.timestamp, event.timestamp);
      expect(restored.metadata, event.metadata);
    });
  });
}
