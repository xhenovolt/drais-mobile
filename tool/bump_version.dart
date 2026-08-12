// Bumps the DRAIS Mobile version everywhere it lives, in one step.
//
// Usage, from the package root:
//
//   dart run tool/bump_version.dart patch
//   dart run tool/bump_version.dart minor
//   dart run tool/bump_version.dart major
//   dart run tool/bump_version.dart build     # re-upload of the same version
//   dart run tool/bump_version.dart 2.0.0     # an explicit version
//
// It updates `pubspec.yaml`, `lib/core/constants/app_version.dart`, and opens
// a `CHANGELOG.md` section — the three places `test/core/app_version_test.dart`
// insists agree.
//
// ## Why a tool rather than a note in CONTRIBUTING
//
// The app sat on 1.0.0+1 through six milestones' worth of features because
// bumping it by hand meant editing three files consistently and nothing ever
// complained. Making the correct thing one command is the only version of
// this that survives a busy week.
//
// The build number always increments, including on a `major`/`minor`/`patch`
// bump. Play and the App Store both reject a repeated build number, and it
// never resets — see docs/VERSIONING.md.

import 'dart:io';

void main(List<String> args) {
  if (args.length != 1) {
    _fail(
      'Usage: dart run tool/bump_version.dart <major|minor|patch|build|X.Y.Z>',
    );
  }

  final File pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    _fail('Run this from the package root — pubspec.yaml is not here.');
  }

  final _Version current = _readCurrent(pubspec);
  final _Version next = _bump(current, args.single);

  if (next.semver == current.semver && next.build == current.build) {
    _fail('That would not change anything (already $current).');
  }

  _writePubspec(pubspec, current, next);
  _writeConstants(next);
  _openChangelogSection(next);

  stdout
    ..writeln('DRAIS Mobile $current → $next')
    ..writeln()
    ..writeln('Updated:')
    ..writeln('  pubspec.yaml')
    ..writeln('  lib/core/constants/app_version.dart')
    ..writeln('  CHANGELOG.md')
    ..writeln()
    ..writeln('Now write the CHANGELOG entry, then:')
    ..writeln('  flutter test test/core/app_version_test.dart');
}

/// A semantic version plus its build number.
class _Version {
  const _Version(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;
  final int build;

  String get semver => '$major.$minor.$patch';

  @override
  String toString() => '$semver+$build';
}

_Version _readCurrent(File pubspec) {
  final String line = pubspec.readAsLinesSync().firstWhere(
        (String l) => l.startsWith('version:'),
        orElse: () => _fail('pubspec.yaml has no version: field.'),
      );
  final RegExpMatch? match =
      RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$').firstMatch(line);
  if (match == null) {
    _fail('Could not parse "$line". Expected `version: X.Y.Z+N`.');
  }
  return _Version(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
  );
}

_Version _bump(_Version v, String how) {
  // Bumping a higher segment resets the lower ones; the build never resets.
  switch (how) {
    case 'major':
      return _Version(v.major + 1, 0, 0, v.build + 1);
    case 'minor':
      return _Version(v.major, v.minor + 1, 0, v.build + 1);
    case 'patch':
      return _Version(v.major, v.minor, v.patch + 1, v.build + 1);
    case 'build':
      return _Version(v.major, v.minor, v.patch, v.build + 1);
    default:
      final RegExpMatch explicit =
          RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(how) ??
              _fail(
                '"$how" is not major, minor, patch, build, or an X.Y.Z '
                'version.',
              );
      return _Version(
        int.parse(explicit.group(1)!),
        int.parse(explicit.group(2)!),
        int.parse(explicit.group(3)!),
        v.build + 1,
      );
  }
}

void _writePubspec(File pubspec, _Version from, _Version to) {
  pubspec.writeAsStringSync(
    pubspec.readAsStringSync().replaceFirst('version: $from', 'version: $to'),
  );
}

void _writeConstants(_Version to) {
  final File file = File('lib/core/constants/app_version.dart');
  if (!file.existsSync()) _fail('${file.path} is missing.');

  String source = file.readAsStringSync();
  source = source
      .replaceFirst(
        RegExp(r"static const String semver = '[^']*';"),
        "static const String semver = '${to.semver}';",
      )
      .replaceFirst(
        RegExp(r'static const int build = \d+;'),
        'static const int build = ${to.build};',
      )
      // The two doc comments quote the version, so they go stale silently
      // otherwise — and a wrong example in a doc comment is worse than none.
      .replaceAll(
        RegExp(r'`DRAISMobile/\d+\.\d+\.\d+ \(build \d+\)`'),
        '`DRAISMobile/${to.semver} (build ${to.build})`',
      )
      .replaceAll(
        RegExp(r'/// `\d+\.\d+\.\d+\+\d+`\.'),
        '/// `$to`.',
      );
  file.writeAsStringSync(source);
}

void _openChangelogSection(_Version to) {
  final File file = File('CHANGELOG.md');
  if (!file.existsSync()) _fail('CHANGELOG.md is missing.');

  final String source = file.readAsStringSync();
  if (source.contains('## [${to.semver}]')) return;

  final DateTime now = DateTime.now();
  final String date = '${now.year}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  // Seeded with a placeholder rather than left empty, so an unfinished entry
  // is obvious in review instead of reading as "nothing changed".
  const String todo = '_Describe the change. Delete this line._';
  final String section = '## [${to.semver}] — $date\n\n$todo\n\n';

  const String marker = '## [Unreleased]\n';
  file.writeAsStringSync(
    source.contains(marker)
        ? source.replaceFirst(marker, '$marker\n$section')
        : '$source\n$section',
  );
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(64); // EX_USAGE
}
