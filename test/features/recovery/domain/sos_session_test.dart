import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/sos_session.dart';

void main() {
  test('SosSession round-trips through JSON with all fields', () {
    final started = DateTime.parse('2026-08-07T18:00:00.000');
    final completed = DateTime.parse('2026-08-07T18:01:30.000');
    final session = SosSession(
      id: 'sos-uuid-1',
      startedAt: started,
      completedAt: completed,
      debrief: 'down',
    );

    final json = session.toJson();
    expect(json['id'], 'sos-uuid-1');
    expect(json['startedAt'], started.toIso8601String());
    expect(json['completedAt'], completed.toIso8601String());
    expect(json['debrief'], 'down');

    final restored = SosSession.fromJson(json);
    expect(restored.id, 'sos-uuid-1');
    expect(restored.startedAt, started);
    expect(restored.completedAt, completed);
    expect(restored.debrief, 'down');
    expect(restored.isCompleted, isTrue);
    expect(restored.duration, const Duration(seconds: 90));
  });

  test('SosSession toJson omits id and debrief when null', () {
    final started = DateTime.parse('2026-08-07T18:00:00.000');
    final session = SosSession(startedAt: started);

    final json = session.toJson();
    expect(json.containsKey('id'), isFalse);
    expect(json.containsKey('debrief'), isFalse);
    expect(json['startedAt'], started.toIso8601String());
    expect(json['completedAt'], isNull);
  });

  test('SosSession fromJson handles legacy JSON without id or debrief', () {
    final json = {
      'startedAt': '2026-08-07T18:00:00.000',
      'completedAt': '2026-08-07T18:01:00.000',
    };

    final session = SosSession.fromJson(json);
    expect(session.id, isNull);
    expect(session.debrief, isNull);
    expect(session.startedAt, DateTime.parse('2026-08-07T18:00:00.000'));
    expect(session.completedAt, DateTime.parse('2026-08-07T18:01:00.000'));
    expect(session.isCompleted, isTrue);
  });

  test(
    'SosSession complete preserves id and updates completedAt and debrief',
    () {
      final started = DateTime.parse('2026-08-07T18:00:00.000');
      final completed = DateTime.parse('2026-08-07T18:02:00.000');
      final active = SosSession(id: 'active-1', startedAt: started);

      final finished = active.complete(completed, 'same');
      expect(finished.id, 'active-1');
      expect(finished.startedAt, started);
      expect(finished.completedAt, completed);
      expect(finished.debrief, 'same');
      expect(finished.isCompleted, isTrue);
    },
  );
}
