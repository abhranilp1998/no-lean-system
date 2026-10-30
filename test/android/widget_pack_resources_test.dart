import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the widget-pack Kotlin, layouts, strings and manifest consistent.
/// RemoteViews fails the whole widget when code touches an id its layout
/// lacks, and an unbounded resize was the bug that started this pack.
void main() {
  const res = 'android/app/src/main/res';
  const kt = 'android/app/src/main/kotlin/com/nolean/no_lean';
  final strings = File('$res/values/strings.xml').readAsStringSync();
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  Set<String> ids(String layout) => RegExp(r'android:id="@\+id/(\w+)"')
      .allMatches(File('$res/layout/$layout.xml').readAsStringSync())
      .map((m) => m.group(1)!)
      .toSet();

  const widgets = {
    'NightTimelineWidgetProvider': (
      'night_timeline_widget_info',
      [
        'night_timeline_widget',
        'night_timeline_widget_compact',
        'night_timeline_row',
      ],
    ),
    'GardenWidgetProvider': ('garden_widget_info', ['garden_widget']),
    'RadarWidgetProvider': ('radar_widget_info', ['radar_widget']),
    'EveningShieldWidgetProvider': (
      'evening_shield_widget_info',
      ['evening_shield_widget', 'evening_shield_widget_compact'],
    ),
  };

  for (final MapEntry(key: provider, value: (info, layouts))
      in widgets.entries) {
    test('$provider: ids, strings, bounded resize, registered', () {
      final source = File('$kt/$provider.kt').readAsStringSync();
      final all = {for (final l in layouts) ...ids(l)};
      for (final m in RegExp(r'R\.id\.(\w+)').allMatches(source)) {
        expect(all, contains(m.group(1)), reason: m.group(1));
      }
      for (final m in RegExp(
        r'R\.(?:string|plurals)\.(\w+)',
      ).allMatches(source)) {
        expect(strings, contains('name="${m.group(1)}"'), reason: m.group(1));
      }
      final xml = File('$res/xml/$info.xml').readAsStringSync();
      expect(xml, contains('android:maxResizeWidth'));
      expect(xml, contains('android:maxResizeHeight'));
      expect(manifest, contains('android:name=".$provider"'));
      expect(manifest, contains('@xml/$info'));
    });
  }

  test('shield compact and full layouts share every always-bound id', () {
    const always = {
      'shield_root',
      'shield_title',
      'shield_countdown',
      'shield_action_ride',
    };
    expect(ids('evening_shield_widget_compact'), always);
    expect(ids('evening_shield_widget'), containsAll(always));
  });

  test('pack text on the home screen stays discreet', () {
    final pack = RegExp(
      r'name="(?:night|garden|radar|shield|wave)_\w+"[^>]*>([^<]*)<',
    ).allMatches(strings).map((m) => m.group(1)!.toLowerCase()).join(' ');
    final plurals = RegExp(
      r'<plurals name="radar_places">([\s\S]*?)</plurals>',
    ).firstMatch(strings)!.group(1)!.toLowerCase();
    for (final word in [
      'lean',
      'relapse',
      'craving',
      'recovery',
      'clean',
      'sober',
      'addict',
      'danger',
      'risk',
      'drug',
      'urge',
    ]) {
      expect('$pack $plurals', isNot(contains(word)), reason: word);
    }
  });

  test('wave entry points: quick tile and widget action', () {
    expect(manifest, contains('.CravingWaveTileService'));
    expect(manifest, contains('BIND_QUICK_SETTINGS_TILE'));
    final service = File(
      'lib/features/recovery/services/widget_action_service.dart',
    ).readAsStringSync();
    expect(service, contains("'wave'"));
    expect(service, contains("'map'"));
  });
}
