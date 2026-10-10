import '../../recovery/domain/recovery_event.dart';

/// One Code Instead task. The id is stable: history refers to it.
class CodeTask {
  const CodeTask(this.id, this.text);

  final String id;
  final String text;
}

/// Ordered catalogue. Append new tasks; never reuse or renumber an id.
const codeTasks = <CodeTask>[
  CodeTask(
    'reverse-string',
    'Write a function that reverses a string without built-in reverse helpers.',
  ),
  CodeTask(
    'three-zones',
    'Build a tiny CLI that prints the current time in three time zones.',
  ),
  CodeTask(
    'split-function',
    'Refactor one function you wrote today into two smaller functions.',
  ),
  CodeTask(
    'fizzbuzz-seven',
    'Solve FizzBuzz, then add a custom rule for multiples of seven.',
  ),
  CodeTask(
    'test-first',
    'Pick one function in a project and write a test that pins its edge case.',
  ),
  CodeTask(
    'word-count',
    'Write a word counter that prints the five most common words in a file.',
  ),
  CodeTask(
    'rename-pass',
    'Rename three unclear variables in your code and re-run it.',
  ),
  CodeTask(
    'parse-date',
    'Parse "2026-10-09 08:00" into a date and print it as "Fri, 9 Oct".',
  ),
];

/// Lengths offered for a block, in minutes.
const codeBlockMinutes = [5, 10, 25];
const defaultCodeBlockMinutes = 10;

/// Sessions shorter than this that the user stops are not recorded.
const minRecordedCodeSession = Duration(minutes: 1);

/// Picks the next task deterministically: the task least recently used in
/// history (never-used tasks first, in catalogue order). Tasks that were
/// abandoned last time get one more turn before finished ones, so a hard
/// task is not silently dropped. Same history, same answer: no randomness.
CodeTask nextCodeTask(Iterable<RecoveryEvent> history, {int skip = 0}) {
  final lastUsed = <String, DateTime>{};
  final lastCompleted = <String, bool>{};
  for (final event in history) {
    if (event.type != RecoveryEventType.codeSession) continue;
    final id = event.metadata['taskId'];
    if (id is! String) continue;
    final previous = lastUsed[id];
    if (previous == null || event.timestamp.isAfter(previous)) {
      lastUsed[id] = event.timestamp;
      lastCompleted[id] = event.metadata['completed'] == true;
    }
  }
  final ranked = List.of(codeTasks)
    ..sort((a, b) {
      final aUsed = lastUsed[a.id];
      final bUsed = lastUsed[b.id];
      if (aUsed == null || bUsed == null) {
        if (aUsed == null && bUsed == null) {
          return codeTasks.indexOf(a).compareTo(codeTasks.indexOf(b));
        }
        return aUsed == null ? -1 : 1;
      }
      final aRetry = lastCompleted[a.id] == false;
      final bRetry = lastCompleted[b.id] == false;
      if (aRetry != bRetry) return aRetry ? -1 : 1;
      return aUsed.compareTo(bUsed);
    });
  return ranked[skip % ranked.length];
}

/// Metadata for a recorded block.
Map<String, Object> codeSessionMetadata({
  required CodeTask task,
  required Duration planned,
  required Duration elapsed,
  required bool completed,
  required String source,
}) => {
  'taskId': task.id,
  'task': task.text,
  'plannedSeconds': planned.inSeconds,
  'durationSeconds': elapsed.inSeconds.clamp(0, planned.inSeconds),
  'completed': completed,
  'source': source,
};
