import 'package:meta/meta.dart';

import 'package:drais/core/config/environment.dart';
import 'package:drais/core/config/server_config.dart';

/// Immutable, build-time application configuration.
///
/// ## Relationship to the LongTerm `.env`
///
/// DRAIS LongTerm's `.env.local` holds ~60 variables. **Almost none of them
/// belong in a mobile binary.** Anything shipped in an APK is readable by
/// anyone who has the APK — there is no such thing as a secret in a mobile
/// client. This class therefore consumes only the *client-appropriate* subset:
///
/// | LongTerm variable         | Mobile equivalent        | Notes                        |
/// |---------------------------|--------------------------|------------------------------|
/// | `NEXT_PUBLIC_APP_URL`     | [defaultApiBaseUrl]      | Optional — see below         |
/// | `NEXT_PUBLIC_APP_NAME`    | [appName]                | Display only                 |
/// | `NEXT_PUBLIC_APP_VERSION` | `AppVersion.semver`      | From `pubspec.yaml`          |
/// | `MAX_FILE_SIZE`           | [maxUploadBytes]         | Client-side pre-validation   |
/// | `SESSION_TIMEOUT_MINUTES` | [sessionIdleTimeout]     | UX hint; server still decides|
///
/// **Deliberately excluded — never add these:** `TIDB_*`, `LOCAL_MYSQL_*`,
/// `DB_*`, `MYSQL_*`, `JWT_SECRET`, `REFRESH_SECRET`, `ENCRYPTION_KEY`,
/// `CONTROL_API_*`, `JETON_API_KEY`, `CLOUDINARY_API_SECRET`,
/// `AFRICASTALKING_*`, `SMTP_*`, `CRON_SECRET`, `ADMIN_SECRET`,
/// `DEVICE_CLAIM_SECRET`.
///
/// The mobile app **never** opens a database connection. Every byte it reads
/// or writes goes through the backend HTTP API, which owns tenant isolation
/// (`getSessionSchoolId`) and RBAC (`requirePermission`). See
/// `docs/adr/M0004-no-business-logic-in-the-client.md`.
class AppConfig {
  /// Builds the active configuration from `--dart-define` values.
  ///
  /// **There is no default server address.** Every screen is compiled into the
  /// binary, so the app opens and renders with no server configured; when data
  /// is first needed it asks. A build may still name a default server, and a
  /// production release normally does.
  factory AppConfig.fromEnvironment() {
    final Environment env = Environment.fromName(
      const String.fromEnvironment('DRAIS_ENV', defaultValue: 'development'),
    );

    return AppConfig._(
      environment: env,
      appName: const String.fromEnvironment(
        'DRAIS_APP_NAME',
        defaultValue: 'DRAIS',
      ),
      // No fallback, deliberately. A build that does not name its server has
      // no server — the app opens, renders, and asks the user which DRAIS to
      // connect to. Guessing "localhost" here is what silently pointed release
      // builds at a developer's laptop.
      defaultApiBaseUrl: ServerConfig.normalise(
        const String.fromEnvironment('DRAIS_API_BASE_URL'),
      ),
      connectTimeout: Duration(
        milliseconds: const int.fromEnvironment(
          'DRAIS_CONNECT_TIMEOUT_MS',
          defaultValue: 15000,
        ),
      ),
      receiveTimeout: Duration(
        milliseconds: const int.fromEnvironment(
          'DRAIS_RECEIVE_TIMEOUT_MS',
          defaultValue: 30000,
        ),
      ),
      sendTimeout: Duration(
        milliseconds: const int.fromEnvironment(
          'DRAIS_SEND_TIMEOUT_MS',
          defaultValue: 60000,
        ),
      ),
      maxRetries: const int.fromEnvironment(
        'DRAIS_MAX_RETRIES',
        defaultValue: 2,
      ),
      maxUploadBytes: const int.fromEnvironment(
        'DRAIS_MAX_FILE_SIZE',
        defaultValue: 10485760, // matches MAX_FILE_SIZE in LongTerm .env
      ),
      sessionIdleTimeout: Duration(
        minutes: const int.fromEnvironment(
          'DRAIS_SESSION_TIMEOUT_MINUTES',
          defaultValue: 60,
        ),
      ),
      defaultPageSize: const int.fromEnvironment(
        'DRAIS_PAGE_SIZE',
        defaultValue: 25,
      ),
      enableNetworkLogging: bool.fromEnvironment(
        'DRAIS_LOG_NETWORK',
        defaultValue: !env.isProduction,
      ),
      allowInsecureHttp: bool.fromEnvironment(
        'DRAIS_ALLOW_INSECURE_HTTP',
        defaultValue: !env.isProduction,
      ),
    );
  }

  const AppConfig._({
    required this.environment,
    required this.appName,
    required this.defaultApiBaseUrl,
    required this.connectTimeout,
    required this.receiveTimeout,
    required this.sendTimeout,
    required this.maxRetries,
    required this.maxUploadBytes,
    required this.sessionIdleTimeout,
    required this.defaultPageSize,
    required this.enableNetworkLogging,
    required this.allowInsecureHttp,
  });

  /// Named constructor for tests, which need a deterministic config.
  @visibleForTesting
  const AppConfig.test({
    this.environment = Environment.development,
    this.appName = 'DRAIS',
    this.defaultApiBaseUrl,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 60),
    this.maxRetries = 0,
    this.maxUploadBytes = 10485760,
    this.sessionIdleTimeout = const Duration(minutes: 60),
    this.defaultPageSize = 25,
    this.enableNetworkLogging = false,
    this.allowInsecureHttp = true,
  });

  /// The environment this binary was built for.
  final Environment environment;

  /// Display name — mirrors `NEXT_PUBLIC_APP_NAME`.
  final String appName;

  /// Build-time **default** server origin, or null when the build names none.
  ///
  /// This is a default, not the answer. The address actually used is resolved
  /// at runtime by `ServerConfig` — a stored user choice wins over this. A
  /// production release normally ships this set to the hosted deployment, so
  /// most users never see the connect screen; a build without it is valid and
  /// simply asks on first launch.
  final String? defaultApiBaseUrl;

  /// Time allowed to establish a TCP/TLS connection.
  final Duration connectTimeout;

  /// Time allowed between response bytes.
  final Duration receiveTimeout;

  /// Time allowed to stream a request body — generous, because uploads on a
  /// Ugandan mobile network are the slow path this app is designed around.
  final Duration sendTimeout;

  /// How many times an idempotent, retry-safe request is retried.
  final int maxRetries;

  /// Client-side upload ceiling — mirrors `MAX_FILE_SIZE`. The server enforces
  /// its own limit; this exists purely to fail fast before wasting bandwidth.
  final int maxUploadBytes;

  /// UX hint for idle-session warnings. **Not** an authority: the server's
  /// 7-day `sessions.expires_at` is the only real session lifetime.
  final Duration sessionIdleTimeout;

  /// Default `limit` for paginated list endpoints.
  final int defaultPageSize;

  /// Whether the network interceptor logs requests and responses.
  final bool enableNetworkLogging;

  /// Whether plain `http://` origins are permitted. False in production, where
  /// an accidental cleartext base URL would leak the session cookie.
  final bool allowInsecureHttp;

  /// Validates the configuration, returning human-readable problems.
  ///
  /// Called once at boot. A non-empty result in production is fatal — we
  /// would rather refuse to start than run a release build that leaks the
  /// session cookie over cleartext or talks to a developer's laptop.
  List<String> validate() {
    final List<String> problems = <String>[];

    // An absent default is valid — the app will ask. Only a *malformed* one
    // is a problem, because it would silently misdirect every request.
    final String? base = defaultApiBaseUrl;
    if (base != null) {
      final Uri? uri = Uri.tryParse(base);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        problems.add('DRAIS_API_BASE_URL is not an absolute URL: $base');
      } else if (uri.scheme == 'http' && !allowInsecureHttp) {
        problems.add(
          'DRAIS_API_BASE_URL uses cleartext http in ${environment.label}. '
          'The session cookie would be transmitted unencrypted.',
        );
      }
      if (environment.isProduction && _looksLikeLocalhost(uri)) {
        problems.add(
          'A production build names a local address as its server ($base). '
          'Nothing on a phone can host DRAIS.',
        );
      }
    }
    if (defaultPageSize <= 0 || defaultPageSize > 200) {
      problems.add('DRAIS_PAGE_SIZE must be between 1 and 200.');
    }
    return problems;
  }

  static bool _looksLikeLocalhost(Uri? uri) {
    if (uri == null) return false;
    const Set<String> local = <String>{
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      '0.0.0.0',
    };
    return local.contains(uri.host) || uri.host.startsWith('192.168.');
  }

  @override
  String toString() =>
      'AppConfig(env: ${environment.id}, '
      'defaultApi: ${defaultApiBaseUrl ?? "(unset — ask on first launch)"}, '
      'pageSize: $defaultPageSize)';
}
