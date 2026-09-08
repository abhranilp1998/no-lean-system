import 'package:flutter_test/flutter_test.dart';

import '../../tool/release_version.dart';

void main() {
  test('reads one authoritative app version and derives the Git tag', () {
    final version = ReleaseVersion.fromPubspec(
      'name: no_lean\nversion: 1.1.0+2\n',
    );
    expect(version.name, '1.1.0');
    expect(version.build, 2);
    expect(version.tag, 'v1.1.0+2');
  });

  test('rejects missing, duplicate, or malformed versions', () {
    for (final text in [
      'name: no_lean\n',
      'version: 1.0.0+1\nversion: 1.1.0+2\n',
    ]) {
      expect(() => ReleaseVersion.fromPubspec(text), throwsFormatException);
    }
    for (final version in [
      '1.0.0',
      '1.0.0+0',
      '01.0.0+1',
      '1.0.0+2100000001',
    ]) {
      expect(() => ReleaseVersion.parse(version), throwsFormatException);
    }
  });

  test('a newer public version cannot reuse or lower the Android build', () {
    final previous = ReleaseVersion.parse('1.0.0+10');
    for (final value in ['1.1.0+9', '2.0.0+10']) {
      expect(
        () => ReleaseVersion.parse(value).requireNewerThan(previous),
        throwsStateError,
      );
    }
  });

  test('a larger build cannot lower the public version', () {
    final previous = ReleaseVersion.parse('1.10.0+10');
    expect(
      () => ReleaseVersion.parse('1.9.0+11').requireNewerThan(previous),
      throwsStateError,
    );
  });

  test('rebuilds keep the public version and advance the build', () {
    ReleaseVersion.parse(
      '1.0.0+11',
    ).requireNewerThan(ReleaseVersion.parse('1.0.0+10'));
  });

  test('all bump levels reserve a build above every known release', () {
    final previous = ReleaseVersion.parse('1.2.3+4');
    for (final entry in {
      'build': '1.2.3+13',
      'patch': '1.2.4+13',
      'minor': '1.3.0+13',
      'major': '2.0.0+13',
    }.entries) {
      expect(
        previous.bump(entry.key, highestBuild: 12).toString(),
        entry.value,
      );
    }
  });

  test('build numbers cannot wrap around the Android limit', () {
    expect(
      () => ReleaseVersion.parse(
        '1.0.0+2100000000',
      ).bump('patch', highestBuild: 1),
      throwsFormatException,
    );
  });
}
