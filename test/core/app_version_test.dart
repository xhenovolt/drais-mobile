import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/constants/app_version.dart';

/// Keeps the version honest.
///
/// ## Why this is a test and not a convention
///
/// The version lives in three places that cannot read each other:
/// `pubspec.yaml` (authoritative, and what Gradle stamps into the APK),
/// `AppVersion` (compile-time, because the `User-Agent` is built where an
/// async `package_info_plus` lookup is not available), and `CHANGELOG.md`.
///
/// The app sat on `1.0.0+1` through direct mode, the Dart server, the whole
/// navigation shell, onboarding, phase 1 and phase 2 — because nothing ever
/// objected. A convention that nothing enforces is not a convention; it is a
/// hope. These tests are the enforcement.
///
/// If one of these fails, do not edit the test. Bump the version.
void main() {
  final RegExp semver = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  String pubspecVersionLine() {
    final File pubspec = File('pubspec.yaml');
    expect(
      pubspec.existsSync(),
      isTrue,
      reason: 'tests must run from the package root',
    );
    final String line = pubspec
        .readAsLinesSync()
        .firstWhere((String l) => l.startsWith('version:'), orElse: () => '');
    expect(line, isNotEmpty, reason: 'pubspec.yaml has no version: field');
    return line.substring('version:'.length).trim();
  }

  test('AppVersion matches pubspec.yaml exactly', () {
    // The two are duplicated out of necessity, so the only thing standing
    // between them and silent divergence is this assertion. A wrong
    // `User-Agent` is invisible until someone is reading `audit_logs` trying
    // to work out which build caused something.
    expect(
      AppVersion.fullVersion,
      pubspecVersionLine(),
      reason: 'lib/core/constants/app_version.dart is out of step with '
          'pubspec.yaml — update both, and CHANGELOG.md',
    );
  });

  test('the version is well-formed semver with a build number', () {
    expect(AppVersion.semver, matches(semver));
    expect(AppVersion.build, greaterThan(0));
    expect(AppVersion.fullVersion, '${AppVersion.semver}+${AppVersion.build}');
  });

  test('CHANGELOG.md has an entry for the current version', () {
    // Every increment is tracked, patches included. A released build whose
    // number appears nowhere in the changelog cannot be explained to anyone
    // later — which is the entire reason for having version numbers.
    final File changelog = File('CHANGELOG.md');
    expect(changelog.existsSync(), isTrue);

    expect(
      changelog.readAsStringSync(),
      contains('[${AppVersion.semver}]'),
      reason: 'CHANGELOG.md has no `## [${AppVersion.semver}]` section — '
          'every version, including a patch, gets an entry',
    );
  });

  test('verifiedAgainstLongTerm is a real LongTerm version', () {
    // A stale value here is the earliest visible symptom of the two
    // repositories drifting apart, so it must at least be shaped like a
    // version rather than a placeholder.
    expect(AppVersion.verifiedAgainstLongTerm, matches(semver));
  });

  test('the User-Agent carries the version', () {
    // The server files this into `sessions.device_info` and
    // `audit_logs.user_agent`. It is how mobile activity is attributed at all.
    expect(AppVersion.userAgent, contains(AppVersion.semver));
    expect(AppVersion.userAgent, contains('${AppVersion.build}'));
    expect(AppVersion.userAgent, startsWith(AppVersion.product));
  });
}
