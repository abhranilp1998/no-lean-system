import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// RemoteViews fails the whole update when code touches an id its layout
/// lacks, so check the night-timeline Kotlin against its layouts.
void main() {
  const res = 'android/app/src/main/res';
  final source = File(
    'android/app/src/main/kotlin/com/nolean/no_lean/NightTimelineWidgetProvider.kt',
  ).readAsStringSync();
  Set<String> ids(String layout) => RegExp(r'android:id="@\+id/(\w+)"')
      .allMatches(File('$res/layout/$layout.xml').readAsStringSync())
      .map((m) => m.group(1)!)
      .toSet();

  test('both sizes share the ids bound for every size', () {
    const shared = {
      'night_root',
      'night_title',
      'night_headline',
      'night_window',
    };
    expect(ids('night_timeline_widget_compact'), shared);
    expect(ids('night_timeline_widget'), {
      ...shared,
      'night_rows',
      'night_action_sos',
    });
    expect(ids('night_timeline_row'), {'night_row_time', 'night_row_mark'});
    final used = RegExp(
      r'R\.id\.(\w+)',
    ).allMatches(source).map((m) => m.group(1)!);
    final all = {...ids('night_timeline_widget'), ...ids('night_timeline_row')};
    for (final id in used) {
      expect(all, contains(id), reason: id);
    }
  });

  test('strings exist and stay discreet', () {
    final strings = File('$res/values/strings.xml').readAsStringSync();
    for (final m in RegExp(r'R\.string\.(\w+)').allMatches(source)) {
      expect(strings, contains('name="${m.group(1)}"'), reason: m.group(1));
    }
    final night = RegExp(
      r'name="night_\w+">([^<]*)<',
    ).allMatches(strings).map((m) => m.group(1)!.toLowerCase()).join(' ');
    for (final word in [
      'lean',
      'relapse',
      'craving',
      'recovery',
      'clean',
      'slipped',
    ]) {
      expect(night, isNot(contains(word)), reason: word);
    }
  });

  test('widget resizes without a maximum, and registered', () {
    final info = File(
      '$res/xml/night_timeline_widget_info.xml',
    ).readAsStringSync();
    expect(info, isNot(contains('maxResize')));
    expect(info, contains('horizontal|vertical'));
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('.NightTimelineWidgetProvider'));
    expect(source, contains('WidgetSizing.views'));
  });
}
