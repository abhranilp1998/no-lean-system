import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/notification_copy.dart';
import 'package:no_lean/features/recovery/domain/notification_policy.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';
import 'package:no_lean/features/zones/domain/position_status.dart';

void main() {
  const hidden = NotificationPrefs(hideSensitive: true);
  const shown = NotificationPrefs();

  test(
    'every Flutter notification is neutral when private notifications are on',
    () {
      final surfaces = everyFlutterNotificationSurface(hidden);
      // Risk window (open + pre), zone, position, code timer, two use-checks,
      // two follow-ups, craving recheck.
      expect(surfaces, hasLength(10));
      expect(
        surfaces.map((s) => s.channel.id).toSet(),
        NotificationChannels.all.map((c) => c.id).toSet(),
      );
      for (final surface in surfaces) {
        expect(surface.lockScreenPublic, isTrue, reason: surface.source);
        expect(surface.hideSensitive, isTrue);
        expect(surface.ticker, surface.title, reason: surface.source);
        expect(surface.subText, isNull, reason: surface.source);
        final text = surface.visibleText;
        final hit = sensitiveNotificationPattern.firstMatch(text);
        expect(
          hit,
          isNull,
          reason: '${surface.source} leaked "${hit?.group(0)}" in:\n$text',
        );
      }
    },
  );

  test(
    'the same catalogue still uses recovery wording when privacy is off',
    () {
      final surfaces = everyFlutterNotificationSurface(shown);
      expect(surfaces.every((s) => s.lockScreenPublic), isFalse);
      final combined = surfaces.map((s) => s.visibleText).join('\n');
      for (final word in [
        'lean',
        'craving',
        'risk',
        'danger',
        'sos',
        'place',
      ]) {
        expect(
          sensitiveNotificationPattern.hasMatch(word),
          isTrue,
          reason: word,
        );
        expect(
          combined.toLowerCase(),
          contains(word),
          reason:
              'public catalogue should still mention "$word" so the '
              'private-mode test is actually covering these sources',
        );
      }
    },
  );

  test(
    'posted Android details carry the surface visibility, ticker and channel',
    () {
      final surface = cravingCheckSurface(prefs: hidden);
      final details = androidDetailsFor(surface);
      expect(details.channelId, NotificationChannels.cravingCheck.id);
      expect(details.channelName, 'Check-in');
      expect(details.channelDescription, 'A follow-up reminder');
      expect(details.ticker, neutralNotificationText.title);
      expect(details.visibility, NotificationVisibility.public);
      expect(details.actions!.map((a) => a.title), ['OPEN', 'LOG']);

      final open = androidDetailsFor(cravingCheckSurface(prefs: shown));
      expect(open.visibility, NotificationVisibility.private);
      expect(open.channelName, 'NO LEAN craving recheck');
      expect(open.ticker, 'CRAVING RECHECK');
    },
  );

  test('position status uses Status, never the app name, when private', () {
    final surface = positionStatusSurface(
      prefs: hidden,
      title: 'INSIDE Depot',
      body: '22.500, 88.300',
    );
    expect(surface.title, neutralPositionTitle);
    expect(surface.title, 'Status');
    expect(surface.visibleText.toLowerCase(), isNot(contains('lean')));
    expect(surface.visibleText, isNot(contains('Depot')));
  });

  test('native Kotlin helpers cover every app-lock notification source', () {
    final kt = File(
      'android/app/src/main/kotlin/com/nolean/no_lean/PrivateNotifications.kt',
    ).readAsStringSync();
    for (final source in nativeNotificationSources) {
      expect(kt, contains('"$source"'), reason: source);
    }
    expect(kt, contains('fun every(hideSensitive: Boolean)'));
    expect(kt, contains('VISIBILITY_PUBLIC'));
    // Private titles must not use the app name (it contains "lean").
    expect(kt, contains('const val REMINDER = "Reminder"'));
    expect(kt, isNot(contains('if (hideSensitive) "NO LEAN"')));
  });

  test('the service posts only through the shared surface builders', () {
    final service = File(
      'lib/features/recovery/services/notification_service.dart',
    ).readAsStringSync();
    for (final builder in [
      'riskWindowSurface',
      'dangerZoneSurface',
      'positionStatusSurface',
      'codeTimerSurface',
      'useCheckSurface',
      'zoneFollowUpSurface',
      'cravingCheckSurface',
      'androidDetailsFor',
      'applyPrivacy',
    ]) {
      expect(service, contains(builder), reason: builder);
    }
    expect(service, isNot(contains("'NO LEAN risk window'")));
    expect(service, isNot(contains("'NO LEAN craving recheck'")));
    expect(service, isNot(contains("'NO LEAN danger zones'")));
  });
}
