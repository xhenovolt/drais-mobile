/// Build and version metadata for DRAIS Mobile.
///
/// The authoritative version lives in `pubspec.yaml` and is read at runtime by
/// `package_info_plus`. The constants here are the *compile-time* mirror used
/// where an async lookup is impractical (the `User-Agent`, crash context, the
/// splash screen). Keep them in step with `pubspec.yaml` — `CHANGELOG.md`
/// records every change to both.
///
/// See `docs/VERSIONING.md` for why mobile starts at 1.0.0 while LongTerm is
/// on 1.173.x, and how the two version lines relate.
library;

/// Compile-time version constants.
abstract final class AppVersion {
  /// Semantic version, matching the `version:` field of `pubspec.yaml`.
  static const String semver = '1.7.2';

  /// Build number, matching the `+N` suffix of `pubspec.yaml`.
  static const int build = 10;

  /// The DRAIS LongTerm version this client's API expectations were last
  /// verified against. Bump it whenever the contract is re-audited — a stale
  /// value here is the earliest visible symptom of the two repositories
  /// drifting apart.
  static const String verifiedAgainstLongTerm = '1.173.45';

  /// Product name used in the `User-Agent` and diagnostics.
  static const String product = 'DRAISMobile';

  /// `DRAISMobile/1.7.2 (build 10)` — sent on every request so the server's
  /// `sessions.device_info` and `audit_logs.user_agent` can attribute
  /// activity to the mobile client.
  static String get userAgent => '$product/$semver (build $build)';

  /// `1.7.2+10`.
  static String get fullVersion => '$semver+$build';
}
