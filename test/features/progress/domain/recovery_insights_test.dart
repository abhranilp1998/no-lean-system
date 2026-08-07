import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/progress/domain/recovery_insights.dart';
import 'package:no_lean/features/recovery/domain/craving_entry.dart';
import 'package:no_lean/features/recovery/domain/sos_session.dart';

void main() {
  test('chronological series sorts newest-first storage into time order', () {
    final later = _craving(DateTime(2026, 8, 7, 20), intensity: 8);
    final earlier = _craving(DateTime(2026, 8, 7, 18), intensity: 5);

    final series = chronologicalCravingSeries([later, earlier]);

    expect(series.map((point) => point.timestamp), [
      earlier.createdAt,
      later.createdAt,
    ]);
  });

  test('trigger and time-of-day breakdowns expose repeat patterns', () {
    final entries = [
      _craving(DateTime(2026, 8, 7, 18), trigger: 'After Work', intensity: 8),
      _craving(DateTime(2026, 8, 6, 19), trigger: 'After Work', intensity: 6),
      _craving(DateTime(2026, 8, 6, 9), trigger: 'Stress', intensity: 4),
    ];

    final triggers = triggerBreakdown(entries);
    final timeBands = timeOfDayBreakdown(entries);

    expect(triggers.first.label, 'After Work');
    expect(triggers.first.count, 2);
    expect(triggers.first.averageIntensity, 7);
    expect(
      timeBands.singleWhere((item) => item.label.startsWith('EVENING')).count,
      2,
    );
  });

  test('SOS summary tracks completions, abandons, and average duration', () {
    final started = DateTime(2026, 8, 7, 18);
    final sessions = [
      SosSession(
        startedAt: started,
        completedAt: started.add(const Duration(seconds: 60)),
      ),
      SosSession(startedAt: started.add(const Duration(hours: 1))),
      SosSession(
        startedAt: started.add(const Duration(hours: 2)),
        completedAt: started.add(const Duration(hours: 2, seconds: 30)),
      ),
    ];

    final summary = sosCompletionSummary(sessions);

    expect(summary.started, 3);
    expect(summary.completed, 2);
    expect(summary.completionRate, closeTo(2 / 3, .001));
    expect(summary.averageDuration, const Duration(seconds: 45));
  });
}

CravingEntry _craving(
  DateTime createdAt, {
  String trigger = 'Other',
  int intensity = 5,
}) => CravingEntry(
  intensity: intensity,
  trigger: trigger,
  note: '',
  createdAt: createdAt,
);
