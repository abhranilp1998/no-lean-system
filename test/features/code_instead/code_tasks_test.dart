import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/code_instead/domain/code_tasks.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/backup_service.dart';

RecoveryEvent session(String taskId, DateTime at, {bool completed = true}) =>
    RecoveryEvent.create(
      type: RecoveryEventType.codeSession,
      timestamp: at,
      metadata: {
        'taskId': taskId,
        'plannedSeconds': 600,
        'durationSeconds': completed ? 600 : 120,
        'completed': completed,
      },
    );

void main() {
  final day = DateTime(2026, 10, 9, 20);

  test('task ids are unique and the catalogue is non-trivial', () {
    expect(codeTasks.map((t) => t.id).toSet(), hasLength(codeTasks.length));
    expect(codeTasks.length, greaterThanOrEqualTo(6));
  });

  test('no history starts at the first task; same history, same task', () {
    expect(nextCodeTask(const []).id, codeTasks.first.id);
    final history = [session(codeTasks[0].id, day)];
    expect(nextCodeTask(history).id, nextCodeTask(history).id);
  });

  test('rotates through unused tasks in catalogue order', () {
    final history = <RecoveryEvent>[];
    final seen = <String>[];
    for (var i = 0; i < codeTasks.length; i++) {
      final task = nextCodeTask(history);
      seen.add(task.id);
      history.add(session(task.id, day.add(Duration(minutes: i))));
    }
    expect(seen, codeTasks.map((t) => t.id).toList());
    // Once all are used, the least recently used comes back first.
    expect(nextCodeTask(history).id, codeTasks.first.id);
  });

  test('a stopped task gets one more turn before finished ones', () {
    final history = [
      for (var i = 0; i < codeTasks.length; i++)
        session(
          codeTasks[i].id,
          day.add(Duration(minutes: i)),
          completed: i != 3,
        ),
    ];
    expect(nextCodeTask(history).id, codeTasks[3].id);
  });

  test('skip walks the same ranking and wraps', () {
    expect(nextCodeTask(const [], skip: 1).id, codeTasks[1].id);
    expect(
      nextCodeTask(const [], skip: codeTasks.length).id,
      codeTasks.first.id,
    );
  });

  test('metadata clamps the duration to the planned block', () {
    final meta = codeSessionMetadata(
      task: codeTasks.first,
      planned: const Duration(minutes: 5),
      elapsed: const Duration(minutes: 9),
      completed: true,
      source: 'widget',
    );
    expect(meta['durationSeconds'], 300);
    expect(meta['source'], 'widget');
    final event = RecoveryEvent.create(
      type: RecoveryEventType.codeSession,
      metadata: meta,
    );
    expect(event.metadata['taskId'], codeTasks.first.id);
  });

  test('code session metadata is validated', () {
    for (final bad in [
      <String, Object>{},
      {
        'taskId': ' ',
        'plannedSeconds': 60,
        'durationSeconds': 1,
        'completed': true,
      },
      {
        'taskId': 'x',
        'plannedSeconds': 0,
        'durationSeconds': 1,
        'completed': true,
      },
      {
        'taskId': 'x',
        'plannedSeconds': 60,
        'durationSeconds': -1,
        'completed': true,
      },
      {
        'taskId': 'x',
        'plannedSeconds': 60,
        'durationSeconds': 1,
        'completed': 'y',
      },
      {
        'taskId': 'x',
        'task': 3,
        'plannedSeconds': 60,
        'durationSeconds': 1,
        'completed': true,
      },
    ]) {
      expect(
        () => RecoveryEvent.create(
          type: RecoveryEventType.codeSession,
          metadata: bad,
        ),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test(
    'backups since format 5 carry code sessions; newer formats are refused',
    () {
      final service = BackupService();
      final event = session('word-count', day);
      final payload = service.buildBackupPayload([
        event,
      ], preferences: const {});
      expect(payload['version'], BackupService.currentBackupVersion);
      expect(payload['version'], greaterThanOrEqualTo(5));
      final preview = service.validateBackupJson(jsonEncode(payload));
      expect(preview.events.single.type, RecoveryEventType.codeSession);
      expect(preview.events.single.metadata['taskId'], 'word-count');
      expect(
        () => service.validateBackupJson(
          jsonEncode({
            'version': BackupService.currentBackupVersion + 1,
            'events': [],
          }),
        ),
        throwsFormatException,
      );
    },
  );
}
