import 'dart:io';

import 'package:dotenv/dotenv.dart';

/// Server configuration, read from the process environment or a `.env` file.
///
/// ## This is the server. Secrets live here and nowhere else.
///
/// The whole point of the split is that this process holds the TiDB
/// credentials and the mobile app does not. Every value below is a secret or
/// an operational setting that must never reach a client binary.
///
/// Precedence matches the DRAIS desktop loader (`electron/config.cjs`):
/// process environment wins over the `.env` file, so a container or systemd
/// unit can override without editing files on disk.
class ServerEnv {
  ServerEnv._({
    required this.tidbHost,
    required this.tidbPort,
    required this.tidbUser,
    required this.tidbPassword,
    required this.tidbDatabase,
    required this.port,
    required this.bindAddress,
    required this.isProduction,
    required this.sessionDays,
    required this.poolSize,
    required this.secureCookies,
  });

  /// Loads configuration, preferring the process environment.
  ///
  /// [envFilePath] is optional; a deployment that injects variables directly
  /// needs no file at all.
  factory ServerEnv.load({String envFilePath = '.env'}) {
    final DotEnv file = DotEnv(includePlatformEnvironment: true);
    if (File(envFilePath).existsSync()) {
      file.load(<String>[envFilePath]);
    }

    String? read(String key) {
      final String? fromProcess = Platform.environment[key];
      if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
      final String? fromFile = file[key];
      return (fromFile == null || fromFile.isEmpty) ? null : fromFile;
    }

    final bool production =
        (read('NODE_ENV') ?? read('DART_ENV') ?? 'development') == 'production';

    return ServerEnv._(
      tidbHost: read('TIDB_HOST'),
      tidbPort: int.tryParse(read('TIDB_PORT') ?? '4000') ?? 4000,
      tidbUser: read('TIDB_USER'),
      tidbPassword: read('TIDB_PASSWORD'),
      tidbDatabase: read('TIDB_DB') ?? 'drais',
      port: int.tryParse(read('PORT') ?? '8080') ?? 8080,
      // 0.0.0.0 so a school's own deployment is reachable from phones on the
      // LAN — the same reason the desktop build binds it.
      bindAddress: read('BIND_ADDRESS') ?? '0.0.0.0',
      isProduction: production,
      sessionDays: int.tryParse(read('SESSION_DAYS') ?? '7') ?? 7,
      poolSize: int.tryParse(read('DB_POOL_SIZE') ?? '5') ?? 5,
      // Secure cookies require HTTPS. A school server on a LAN runs plain
      // HTTP, so this must be overridable independently of NODE_ENV —
      // otherwise a production LAN deployment sets Secure and the cookie is
      // silently never sent back.
      secureCookies:
          (read('SECURE_COOKIES') ?? (production ? 'true' : 'false')) == 'true',
    );
  }

  /// TiDB Cloud hostname.
  final String? tidbHost;

  /// TiDB port — 4000 by default, not MySQL's 3306.
  final int tidbPort;

  /// TiDB user, in TiDB Cloud's `<prefix>.root` form.
  final String? tidbUser;

  /// TiDB password. Never logged, never returned by any endpoint.
  final String? tidbPassword;

  /// Database name.
  final String tidbDatabase;

  /// Port this server listens on.
  final int port;

  /// Interface to bind. `0.0.0.0` makes a school deployment LAN-reachable.
  final String bindAddress;

  /// Whether this is a production deployment.
  final bool isProduction;

  /// Session lifetime. Matches the platform's 7 days.
  final int sessionDays;

  /// Connection pool size.
  ///
  /// Deliberately small. TiDB Cloud caps concurrent connections, and this is
  /// exactly the pressure that would have become unmanageable had every phone
  /// held its own pool.
  final int poolSize;

  /// Whether to mark cookies `Secure`.
  final bool secureCookies;

  /// Whether the database is configured at all.
  bool get hasDatabase =>
      tidbHost != null && tidbUser != null && tidbPassword != null;

  /// Configuration problems that must stop the server starting.
  List<String> validate() {
    final List<String> problems = <String>[];
    if (tidbHost == null) problems.add('TIDB_HOST is not set.');
    if (tidbUser == null) problems.add('TIDB_USER is not set.');
    if (tidbPassword == null) problems.add('TIDB_PASSWORD is not set.');
    if (port <= 0 || port > 65535) problems.add('PORT is out of range.');
    return problems;
  }

  /// Credential-free summary, safe to log at boot.
  Map<String, Object?> get safeSummary => <String, Object?>{
        'host': tidbHost,
        'port': tidbPort,
        'database': tidbDatabase,
        'user_set': tidbUser != null,
        'password_set': tidbPassword != null,
        'bind': '$bindAddress:$port',
        'production': isProduction,
        'secure_cookies': secureCookies,
      };
}
