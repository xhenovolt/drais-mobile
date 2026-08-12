# Versioning

DRAIS Mobile follows the same versioning philosophy as DRAIS LongTerm, on its own number line.

## Mobile starts at 1.0.0

LongTerm is on **1.173.15**. Mobile starts at **1.0.0**.

The numbers are not aligned, and should not be. `1.0.0` marks the birth of the mobile platform — a genuine first release, not release 174 of something else. Pinning mobile to the web version would mean either fabricating 172 releases that never happened, or bumping the mobile version every time an unrelated web fix ships.

What *is* shared is the **rules**, so an engineer moving between the repositories reads a version number the same way in both.

## The rules

Identical to LongTerm's `CONTRIBUTING.md`:

| Segment | When |
|---|---|
| **MAJOR** | Breaking change — `feat!:`, `fix!:`, or `BREAKING CHANGE` in the body |
| **MINOR** | New feature — `feat:` |
| **PATCH** | Everything else — the default |

Bumping a higher segment resets the lower ones: `1.4.7` + `feat:` → `1.5.0`.

For mobile, "breaking" means something a **user** experiences as a break — a forced re-login, a lost local cache, a minimum backend version the app now requires — not an internal refactor.

## Bumping it

One command, from the package root:

```bash
dart run tool/bump_version.dart patch    # 1.7.2 → 1.7.3
dart run tool/bump_version.dart minor    # 1.7.2 → 1.8.0
dart run tool/bump_version.dart major    # 1.7.2 → 2.0.0
dart run tool/bump_version.dart build    # re-upload, same version
dart run tool/bump_version.dart 2.0.0    # explicit
```

It updates `pubspec.yaml`, `lib/core/constants/app_version.dart` (including the doc comments that quote the version), and opens a dated `CHANGELOG.md` section for you to fill in. The build number always increments and never resets.

**Every increment gets tracked, patches included.** `test/core/app_version_test.dart` fails the suite if `AppVersion` and `pubspec.yaml` disagree, if the version is malformed, or if `CHANGELOG.md` has no section for the current version. This exists because the app sat on `1.0.0+1` through six milestones' worth of features — a convention nothing enforces is a hope, not a convention.

## Building a named artefact

```bash
tool/build.sh apk debug          # build/drais-1.7.2-debug.apk
tool/build.sh apk release        # build/drais-1.7.2-release.apk
tool/build.sh appbundle release  # build/drais-1.7.2-release.aab
```

`android/app/build.gradle.kts` names the Gradle output `drais-<version>-<channel>.apk` via the AGP 9 variant API. The Flutter Gradle plugin then copies it to `build/app/outputs/flutter-apk/app-<channel>.apk` using a filename it hardcodes, and that copy is the path `flutter build` prints — there is no hook to change it. The script promotes the correctly named file to the top of `build/` and deletes the ambiguous copy, so exactly one artefact remains and nobody ships `app-debug.apk` by grabbing the first file they see.

## Where the version lives

| Location | Purpose |
|---|---|
| `pubspec.yaml` → `version: 1.7.2+10` | Authoritative. Feeds Android `versionName`/`versionCode` and iOS `CFBundleShortVersionString`/`CFBundleVersion`. |
| `lib/core/constants/app_version.dart` | Compile-time mirror, for the `User-Agent`, splash and diagnostics. |
| `CHANGELOG.md` | Human record of every release. |

`AppVersion.semver` and `AppVersion.build` **must** match `pubspec.yaml`. They are duplicated because reading `package_info_plus` is async and unavailable where the `User-Agent` is constructed. Changing one without the other is caught in review, and `CHANGELOG.md` records both.

### The build number

`+N` increments on **every** store upload, including a re-upload of an identical version. Google Play and the App Store both reject a repeated build number. It never resets.

## `verifiedAgainstLongTerm`

```dart
static const String verifiedAgainstLongTerm = '1.173.15';
```

The LongTerm version this client's API expectations were last audited against.

This is the single most important number in the repository for preventing drift. Mobile consumes the **internal** API, which — unlike the frozen Platform API ([ADR-0011](platform/0011-platform-api-contract-freeze.md)) — is explicitly free to change. A stale value here is the earliest visible symptom of the two codebases separating.

Update it, [PARITY](PARITY.md) and `docs/platform/` together, in one commit, whenever:

- LongTerm ships a MAJOR or MINOR release;
- a mobile integration meets an unexpected response;
- a new endpoint is consumed.

## Releasing

```bash
# 1. Update pubspec.yaml and app_version.dart together
# 2. Write the CHANGELOG entry
# 3. Verify
flutter analyze && flutter test
# 4. Build
flutter build appbundle --release --dart-define-from-file=env/production.json
# 5. Tag
git tag mobile-v1.0.0
git push origin main --tags
```

Tags are prefixed `mobile-v` so that mobile and platform tags remain distinguishable if the repositories ever share a remote.

## Compatibility with LongTerm

The app sends `X-DRAIS-Client: mobile` and `X-DRAIS-Client-Version` on every request. Nothing consumes them today; they exist so that the server *can* — for analytics, or eventually to refuse a client below a minimum version.

**A minimum-version gate is the right mechanism when the internal API makes a breaking change**, and is the recommended follow-up before the first module ships. Without it, a school running a six-month-old APK meets a changed contract as a `MalformedResponseFailure` — which the client at least names honestly ("DRAIS returned data this version of the app does not understand. Please update the app.") rather than showing a blank screen.

## Release notes

LongTerm keeps `docs/releases/vX.Y.Z.md`. Mobile keeps a single `CHANGELOG.md` until release volume makes per-release files worthwhile — one file is easier to read at this size, and the format follows Keep a Changelog so splitting it later is mechanical.
