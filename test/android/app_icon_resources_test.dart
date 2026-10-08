import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/services/notification_service.dart';

/// Regression: the notification small icon used to be the full-colour,
/// alpha-less 1254 px logo in `drawable/` (mdpi), which Android renders as a
/// solid square and decodes at ~2.75x on xxhdpi phones. It is resolved by
/// name from Dart, so the release resource shrinker cannot see it either.
void main() {
  const res = 'android/app/src/main/res';

  test('notification small icon is a kept, single-colour vector', () {
    final icon = File('$res/drawable/$notificationSmallIcon.xml');
    expect(icon.existsSync(), isTrue);
    final xml = icon.readAsStringSync();
    expect(xml, contains('<vector'));
    final colours = RegExp(
      r'android:fillColor="([^"]+)"',
    ).allMatches(xml).map((m) => m.group(1)!.toUpperCase()).toSet();
    expect(colours, {'#FFFFFFFF'});

    final keep = File('$res/raw/keep.xml').readAsStringSync();
    expect(keep, contains('@drawable/$notificationSmallIcon'));
    expect(
      File(
        'lib/features/recovery/services/notification_service.dart',
      ).readAsStringSync(),
      contains('AndroidInitializationSettings(notificationSmallIcon)'),
    );
  });

  test('launcher icon is a density-bucketed mipmap of sane size', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final name = RegExp(
      r'android:icon="@mipmap/(\w+)"',
    ).firstMatch(manifest)?.group(1);
    expect(name, isNotNull, reason: 'app icon must come from mipmap');
    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final MapEntry(key: density, value: size) in sizes.entries) {
      final bytes = File('$res/mipmap-$density/$name.png').readAsBytesSync();
      final header = ByteData.sublistView(bytes, 16, 24);
      expect(header.getUint32(0), size, reason: density);
      expect(header.getUint32(4), size, reason: density);
    }
    // No oversized bitmaps left in density-less or mdpi drawables.
    for (final file in Directory('$res/drawable').listSync()) {
      if (file.path.endsWith('.png')) {
        expect((file as File).lengthSync(), lessThan(200 * 1024));
      }
    }
  });
}
