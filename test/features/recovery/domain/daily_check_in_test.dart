import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/daily_check_in.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/domain/risk_window.dart';
import 'package:no_lean/features/recovery/services/check_in_inbox.dart';

/// PR #33's list of words a private notification must never show. Kept here
/// until #33 merges; after that, use `sensitiveNotificationPattern` from
/// notification_copy.dart and add the check-in to its surface catalogue.
const _sensitiveWords = [
  'lean',
  'codeine',
  'benzo',
  'craving',
  'relapse',
  'clean',
  'place',
  'places',
  'sober',
  'addict',
  'recovery',
  'danger',
  'risk',
  'drug',
  'urge',
  'sos',
];
final _sensitive = RegExp(
  r'\b(?:' + _sensitiveWords.join('|') + r')s?\b',
  caseSensitive: false,
);

void main() {
  test(
    'private wording passes the no-sensitive-words check on every string',
    () {
      final copy = dailyCheckInCopy(hideSensitive: true);
      final strings = [
        ...copy.visibleStrings,
        dailyCheckInChannel.privateName,
        dailyCheckInChannel.privateDescription,
      ];
      for (final text in strings) {
        expect(_sensitive.hasMatch(text), isFalse, reason: text);
      }
      expect(copy.title, 'Daily check-in');
      expect(copy.okayLabel, 'GOOD');
      expect(copy.strugglingLabel, 'ROUGH');
      expect(copy.usedLabel, 'SLIPPED');
    },
  );

  test('public wording names the three answers', () {
    final copy = dailyCheckInCopy(hideSensitive: false);
    expect(copy.okayLabel, 'OKAY');
    expect(copy.strugglingLabel, 'STRUGGLING');
    expect(copy.usedLabel, 'USED');
    expect(copy.body, contains('Okay, Struggling, or Used'));
  });

  test('every action id is distinct and only two run in the background', () {
    final ids = {
      checkInOkayAction,
      checkInUsedAction,
      checkInUsedOpenAction,
      checkInStrugglingAction,
    };
    expect(ids.length, 4);
    expect(checkInAnswerFor(checkInOkayAction), CheckInAnswer.okay);
    expect(checkInAnswerFor(checkInUsedAction), CheckInAnswer.used);
    expect(checkInAnswerFor(checkInUsedOpenAction), isNull);
    expect(checkInAnswerFor(checkInStrugglingAction), isNull);
    expect(checkInAnswerFor(null), isNull);
    expect(dailyCheckInId, 730);
  });

  test('quiet hours keep the check-in silent and the settings say so', () {
    const prefs = NotificationPrefs(
      quietHoursEnabled: true,
      quietHours: RiskWindow(startMinutes: 22 * 60, endMinutes: 7 * 60),
    );
    expect(checkInInQuietHours(prefs, defaultCheckInMinutes), isFalse);
    expect(checkInInQuietHours(prefs, 23 * 60), isTrue);
    expect(checkInInQuietHours(prefs, 6 * 60 + 59), isTrue);
    expect(checkInInQuietHours(const NotificationPrefs(), 23 * 60), isFalse);
    expect(
      dailyCheckInSubtitle(enabled: true, minutes: 23 * 60, prefs: prefs),
      contains('inside quiet hours'),
    );
    expect(
      dailyCheckInSubtitle(
        enabled: true,
        minutes: defaultCheckInMinutes,
        prefs: prefs,
      ),
      startsWith('Every day at 20:00'),
    );
    expect(
      dailyCheckInSubtitle(
        enabled: false,
        minutes: defaultCheckInMinutes,
        prefs: prefs,
      ),
      startsWith('Off'),
    );
    expect(NotificationKind.dailyCheckIn.isCritical, isFalse);
  });

  test('minutes outside a day or of the wrong type fall back', () {
    expect(checkInMinutesFrom(75, 1200), 75);
    expect(checkInMinutesFrom(-1, 1200), 1200);
    expect(checkInMinutesFrom(1440, 1200), 1200);
    expect(checkInMinutesFrom('20:00', 1200), 1200);
    expect(checkInMinutesFrom(null, 1200), 1200);
    expect(checkInMinutesFrom(600.5, 1200), 1200);
  });

  test('inbox entries round-trip and malformed ones are refused', () {
    final entry = CheckInEntry(
      id: 'abc',
      answer: CheckInAnswer.used,
      at: DateTime(2026, 11, 26, 20, 41),
    );
    final back = CheckInEntry.tryDecode(jsonDecode(entry.encode()));
    expect(back?.id, 'abc');
    expect(back?.answer, CheckInAnswer.used);
    expect(back?.at, DateTime(2026, 11, 26, 20, 41));
    expect(CheckInEntry.tryDecode({'id': 'x', 'answer': 'okay'}), isNull);
    expect(
      CheckInEntry.tryDecode({'id': '', 'answer': 'okay', 'at': 'now'}),
      isNull,
    );
    expect(
      CheckInEntry.tryDecode({
        'id': 'x',
        'answer': 'maybe',
        'at': '2026-01-01T00:00:00',
      }),
      isNull,
    );
    expect(CheckInEntry.tryDecode('nope'), isNull);
  });

  test(
    'the file inbox drains once, survives a torn line and replays safely',
    () async {
      final dir = await Directory.systemTemp.createTemp('check_in_inbox');
      addTearDown(() => dir.delete(recursive: true));
      final inbox = FileCheckInInbox(directory: dir);
      expect(await inbox.drain(), isEmpty);
      await inbox.append(
        CheckInEntry(
          id: 'a',
          answer: CheckInAnswer.okay,
          at: DateTime(2026, 11, 26, 20),
        ),
      );
      await File(
        '${dir.path}/check_in_answers.jsonl',
      ).writeAsString('{"id":"torn"\n', mode: FileMode.append);
      await inbox.append(
        CheckInEntry(
          id: 'b',
          answer: CheckInAnswer.used,
          at: DateTime(2026, 11, 26, 20, 5),
        ),
      );
      final first = await inbox.drain();
      expect(first.map((e) => e.id), ['a', 'b']);
      // Not acknowledged yet: a crash before saving drains the same entries.
      expect((await inbox.drain()).map((e) => e.id), ['a', 'b']);
      // A new answer while draining starts a fresh file.
      await inbox.append(
        CheckInEntry(
          id: 'c',
          answer: CheckInAnswer.okay,
          at: DateTime(2026, 11, 26, 21),
        ),
      );
      await inbox.acknowledge();
      expect((await inbox.drain()).map((e) => e.id), ['c']);
      await inbox.acknowledge();
      expect(await inbox.drain(), isEmpty);
    },
  );
}
