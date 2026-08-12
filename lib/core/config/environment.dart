/// Deployment environments DRAIS Mobile can be built for.
///
/// The selected environment is fixed **at build time** via `--dart-define`,
/// never at runtime. This mirrors ADR-0010's rule in DRAIS LongTerm: a
/// deployment cannot be re-pointed at a different backend by any UI action.
///
/// ```bash
/// flutter run --dart-define=DRAIS_ENV=development
/// flutter build apk --release --dart-define-from-file=env/production.json
/// ```
library;

/// The four environments the DRAIS platform is deployed to.
enum Environment {
  /// Local development against `next dev` (or a LAN-hosted desktop build).
  development,

  /// Shared pre-production environment fed from `main`.
  staging,

  /// Manual verification environment with production-shaped data.
  qa,

  /// Live tenants. Verbose logging and diagnostic surfaces are disabled.
  production;

  /// Parses the `DRAIS_ENV` dart-define value.
  ///
  /// An unrecognised or absent value resolves to [Environment.development] —
  /// deliberately the *least* privileged default, so a misconfigured release
  /// build fails loudly against a dev API rather than silently reaching
  /// production.
  static Environment fromName(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'production':
      case 'prod':
        return Environment.production;
      case 'staging':
      case 'stage':
        return Environment.staging;
      case 'qa':
        return Environment.qa;
      case 'development':
      case 'dev':
      default:
        return Environment.development;
    }
  }

  /// Stable lowercase identifier used in logs, headers and diagnostics.
  String get id => name;

  /// Human-readable label for the diagnostics screen.
  String get label => switch (this) {
    Environment.development => 'Development',
    Environment.staging => 'Staging',
    Environment.qa => 'QA',
    Environment.production => 'Production',
  };

  /// Whether this environment is a live tenant environment.
  bool get isProduction => this == Environment.production;

  /// Whether non-production diagnostics (env banner, request/response bodies
  /// in logs, the diagnostics screen) may be shown.
  bool get allowsDiagnostics => this != Environment.production;
}
