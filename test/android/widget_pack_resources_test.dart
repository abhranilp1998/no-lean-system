import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the widget-pack Kotlin, layouts, strings and manifest consistent.
/// RemoteViews fails the whole widget when code touches an id its layout
/// lacks. Resizing is deliberately unbounded (no maxResize*): every layout
/// fills and scales instead, up to a full screen.
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
    'NoteWidgetProvider': ('note_widget_info', ['note_widget']),
  };

  for (final MapEntry(key: provider, value: (info, layouts))
      in widgets.entries) {
    test('$provider: ids, strings, unbounded resize, registered', () {
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
      expect(xml, isNot(contains('maxResize')));
      expect(xml, contains('horizontal|vertical'));
      expect(source, contains('WidgetSizing.views'));
      for (final l in layouts.where((l) => !l.endsWith('_row'))) {
        final root = File('$res/layout/$l.xml').readAsStringSync();
        expect(
          RegExp(r'layout_height="match_parent"').hasMatch(root),
          isTrue,
          reason: '$l must fill the widget',
        );
      }
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
      r'name="(?:night|garden|radar|shield|wave|note)_\w+"[^>]*>([^<]*)<',
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
      'letter',
      'future',
    ]) {
      expect('$pack $plurals', isNot(contains(word)), reason: word);
    }
  });

  test('note widget never carries note text', () {
    final source = File('$kt/NoteWidgetProvider.kt').readAsStringSync();
    expect(source, isNot(contains('getString(WidgetPack.KEY')));
    final sync = File(
      'lib/features/widgets/services/fullscreen_widget_sync.dart',
    ).readAsStringSync();
    expect(sync, isNot(contains('.text')));
    expect(sync, contains("args['hasNotes'] = noteCount > 0"));
  });

  test('the existing NO LEAN widget turns into the pack when stretched', () {
    final source = File('$kt/NoLeanWidgetProvider.kt').readAsStringSync();
    expect(source, contains('WidgetSizing.views'));
    expect(source, contains('EveningShieldWidgetProvider.buildNow'));
    expect(source, contains('NightTimelineWidgetProvider.buildNow'));
    expect(source, contains('GardenWidgetProvider.build'));
    expect(source, contains('onAppWidgetOptionsChanged'));
    for (final info in ['no_lean_widget_info', 'no_lean_widget_large_info']) {
      expect(
        File('$res/xml/$info.xml').readAsStringSync(),
        isNot(contains('maxResize')),
      );
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
    expect(service, contains("'letter'"));
  });
}
