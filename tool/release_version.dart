import 'dart:io';

/// App releases are independent of recovery-state and backup schema versions.
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;
  final int build;
  static const maxBuild = 2100000000;

  factory ReleaseVersion.parse(String input) {
    final match = RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)$',
    ).firstMatch(input);
    if (match == null) {
      throw FormatException('Expected MAJOR.MINOR.PATCH+BUILD, got $input.');
    }
    final parts = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
    if (parts[3] > maxBuild) {
      throw const FormatException('Build number exceeds the Android limit.');
    }
    return ReleaseVersion(parts[0], parts[1], parts[2], parts[3]);
  }

  factory ReleaseVersion.fromPubspec(String content) {
    final matches = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).allMatches(content);
    if (matches.length != 1) {
      throw const FormatException('pubspec.yaml needs exactly one version.');
    }
    return ReleaseVersion.parse(matches.single.group(1)!);
  }

  String get name => '$major.$minor.$patch';
  String get tag => 'v$this';

  @override
  String toString() => '$name+$build';

  /// Compare the public version; build ordering is checked separately.
  @override
  int compareTo(ReleaseVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final difference = pair.$1.compareTo(pair.$2);
      if (difference != 0) return difference;
    }
    return 0;
  }

  void requireNewerThan(ReleaseVersion previous) {
    if (compareTo(previous) < 0 || build <= previous.build) {
      throw StateError(
        '$this must not lower the app version and must use a build number '
        'greater than ${previous.build} (previous: $previous).',
      );
    }
  }

  ReleaseVersion bump(String part, {required int highestBuild}) {
    final nextBuild = (highestBuild > build ? highestBuild : build) + 1;
    final nextName = switch (part) {
      'build' => name,
      'patch' => '$major.$minor.${patch + 1}',
      'minor' => '$major.${minor + 1}.0',
      'major' => '${major + 1}.0.0',
      _ => throw ArgumentError('Choose build, patch, minor, or major.'),
    };
    return ReleaseVersion.parse('$nextName+$nextBuild');
  }
}

Future<String> _git(List<String> arguments) async {
  final result = await Process.run('git', arguments);
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

Future<List<ReleaseVersion>> _releases() async {
  final tags = await _git(['tag', '--list', 'v*']);
  final releases = <ReleaseVersion>[];
  for (final tag in tags.split('\n').where((tag) => tag.isNotEmpty)) {
    // Legacy tags without a build number cannot establish Android ordering.
    if (!tag.contains('+')) continue;
    releases.add(ReleaseVersion.parse(tag.substring(1).trim()));
  }
  return releases;
}

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty ||
        !['check', 'bump', 'tag'].contains(arguments.first)) {
      throw ArgumentError(
        'Usage: dart tool/release_version.dart '
        'check [--base-ref=REF] [--tag=TAG] | '
        'bump build|patch|minor|major | tag',
      );
    }
    final pubspec = File('pubspec.yaml');
    final content = await pubspec.readAsString();
    var version = ReleaseVersion.fromPubspec(content);
    final releases = await _releases();
    final command = arguments.first;

    if (command == 'bump') {
      if (arguments.length != 2) throw ArgumentError('Specify a bump level.');
      final highest = releases.fold<int>(
        version.build,
        (best, release) => release.build > best ? release.build : best,
      );
      version = version.bump(arguments[1], highestBuild: highest);
      for (final release in releases) {
        version.requireNewerThan(release);
      }
      await pubspec.writeAsString(
        content.replaceFirst(
          RegExp(r'^version:[^\r\n]*', multiLine: true),
          'version: $version',
        ),
      );
      stdout.writeln('Prepared $version in pubspec.yaml; no tag was created.');
      return;
    }

    String? checkedTag;
    for (final argument in arguments.skip(1)) {
      if (command == 'check' && argument.startsWith('--base-ref=')) {
        final ref = argument.substring('--base-ref='.length);
        final commit = await _git([
          'rev-parse',
          '--verify',
          '--end-of-options',
          '$ref^{commit}',
        ]);
        final previous = ReleaseVersion.fromPubspec(
          await _git(['show', '$commit:pubspec.yaml']),
        );
        version.requireNewerThan(previous);
      } else if (command == 'check' && argument.startsWith('--tag=')) {
        checkedTag = argument.substring('--tag='.length);
        if (checkedTag != version.tag) {
          throw StateError('Tag $checkedTag must match ${version.tag}.');
        }
        final tagCommit = await _git(['rev-parse', '$checkedTag^{commit}']);
        if (tagCommit != await _git(['rev-parse', 'HEAD'])) {
          throw StateError('The tag must identify the checked-out commit.');
        }
      } else {
        throw ArgumentError('Unsupported argument: $argument');
      }
    }
    for (final release in releases) {
      if (release.tag == checkedTag) continue;
      version.requireNewerThan(release);
    }

    if (command == 'tag') {
      if (await _git(['branch', '--show-current']) != 'main') {
        throw StateError('Create release tags from reviewed main only.');
      }
      if ((await _git(['status', '--porcelain'])).isNotEmpty) {
        throw StateError('Commit the release changes before creating a tag.');
      }
      await _git(['tag', '-a', version.tag, '-m', 'NO LEAN $version']);
      stdout.writeln('Created ${version.tag} locally. Nothing was pushed.');
    } else {
      stdout.writeln('Release version OK: $version (${version.tag}).');
    }
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
