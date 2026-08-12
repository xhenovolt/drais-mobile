import 'dart:io';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';

import 'package:drais/core/logging/app_logger.dart';

/// How this installation reaches DRAIS data.
enum DataMode {
  /// Talk to a DRAIS server over HTTP — hosted, or one running on the LAN.
  ///
  /// No credentials on the device. The server enforces tenant isolation and
  /// RBAC, and the app renders what it is given.
  api,

  /// Talk to TiDB Cloud directly, in-process.
  ///
  /// The app *is* the backend: it opens the connection, runs the queries and
  /// enforces the rules itself, with no separate server and no address to
  /// enter. This is the topology of the Next.js desktop build, where the API
  /// routes live inside the same executable.
  direct,
}

/// TiDB connection settings for [DataMode.direct].
///
/// ## These are read from a file, never compiled in
///
/// The credential is **not** a `--dart-define` and must never become one:
/// dart-defines are baked into the binary, and an APK or a desktop bundle is
/// an archive anyone can open.
///
/// Instead this mirrors the precedence the DRAIS desktop build already uses in
/// `electron/config.cjs` — an operator places a `drais.env` file, and the
/// application reads it at startup. The credential is provisioned per
/// installation rather than shipped to every installation, so rotating it does
/// not mean re-releasing the app.
///
/// ## Where the config comes from, highest priority first
///
/// 1. **`drais.env` beside the executable** (desktop) — an operator drops it in
///    without knowing platform conventions.
/// 2. **`drais.env` in the working directory** (desktop, `flutter run`).
/// 3. **`drais.env` in the app support directory** — the per-device path on
///    Android, writable at runtime.
/// 4. **`assets/drais.env` bundled in the build** — the fallback that makes a
///    distributed APK work on install, with nothing to place.
///
/// This is the precedence `electron/config.cjs` already uses in the DRAIS
/// desktop build: a provisioned file wins over the shipped default, so a
/// credential can be rotated on one machine without re-releasing.
///
/// If nothing is found, [DataMode.direct] is unavailable and the app runs in
/// [DataMode.api]. Absence is not an error.
///
/// ## The bundled asset is a real exposure
///
/// An APK is a zip file. A credential in `assets/` can be read by anyone
/// holding the file — no rooting, no cleverness. Use it for builds that go to
/// devices the school controls; for handsets, ship without the asset and let
/// the app use a DRAIS server. See `docs/DEPLOYMENT_MODES.md`.
class DirectDbConfig {
  /// Creates a direct-connection configuration.
  const DirectDbConfig({
    required this.host,
    required this.port,
    required this.user,
    required this.password,
    required this.database,
  });

  /// TiDB Cloud hostname.
  final String host;

  /// TiDB port — 4000, not MySQL's 3306.
  final int port;

  /// Database user.
  final String user;

  /// Database password. Never logged; [toString] omits it.
  final String password;

  /// Database name.
  final String database;

  /// Loads configuration from the first `drais.env` found.
  ///
  /// Returns null when no file exists or it lacks the required keys — the
  /// normal case, meaning this installation uses the API.
  static Future<DirectDbConfig?> load(AppLogger logger) async {
    final AppLogger log = logger.child('DirectDb');

    for (final String path in await _candidatePaths()) {
      final File file = File(path);
      if (!file.existsSync()) continue;

      try {
        final Map<String, String> values = _parse(await file.readAsString());
        final DirectDbConfig? config = _fromValues(values);

        if (config == null) {
          log.warn(
            'Found a config file but it is missing TIDB_HOST/USER/PASSWORD.',
            context: <String, Object?>{'path': path},
          );
          continue;
        }

        log.info(
          'Direct database mode configured.',
          context: <String, Object?>{
            'path': path,
            'host': config.host,
            'database': config.database,
          },
        );
        return config;
      } on Object catch (e) {
        // An unreadable config must not stop the app booting — it falls back
        // to API mode and says why.
        log.warn(
          'Could not read the direct database config.',
          context: <String, Object?>{'path': path, 'reason': e.runtimeType},
        );
      }
    }

    // Last resort: a config bundled into the build. This is what lets an
    // installed APK work with nothing to place on the device.
    final DirectDbConfig? bundled = await _loadBundled(log);
    if (bundled != null) return bundled;

    log.debug('No direct database config found; using API mode.');
    return null;
  }

  /// Reads `assets/drais.env` from the build, when one was bundled.
  ///
  /// A missing asset is the normal case and throws inside Flutter's asset
  /// loader, so the exception is swallowed rather than logged as a problem.
  static Future<DirectDbConfig?> _loadBundled(AppLogger log) async {
    try {
      final String contents = await rootBundle.loadString('assets/drais.env');
      final DirectDbConfig? config = _fromValues(_parse(contents));

      if (config != null) {
        log.info(
          'Direct database mode configured from the bundled asset.',
          context: <String, Object?>{
            'host': config.host,
            'database': config.database,
          },
        );
      }
      return config;
    } on Object {
      // No asset bundled — the expected path for a build that uses a server.
      return null;
    }
  }

  /// Paths searched, in order. Beside the executable first, so an operator can
  /// drop the file next to the app without knowing platform conventions.
  static Future<List<String>> _candidatePaths() async {
    final List<String> paths = <String>[];

    if (!Platform.isAndroid && !Platform.isIOS) {
      final String exeDir = File(Platform.resolvedExecutable).parent.path;
      paths.add('$exeDir/drais.env');
      paths.add('${Directory.current.path}/drais.env');
    }

    try {
      final Directory support = await getApplicationSupportDirectory();
      paths.add('${support.path}/drais.env');
    } on Object {
      // Platform channel unavailable (e.g. a unit test) — the paths above
      // are still worth trying.
    }

    return paths;
  }

  /// Parses `drais.env` contents into a configuration.
  ///
  /// Exposed so the file placed on a machine can be validated without a
  /// platform channel — a malformed config should fail a test, not a launch.
  @visibleForTesting
  static DirectDbConfig? parse(String contents) =>
      _fromValues(_parse(contents));

  static DirectDbConfig? _fromValues(Map<String, String> v) {
    final String? host = v['TIDB_HOST'];
    final String? user = v['TIDB_USER'];
    final String? password = v['TIDB_PASSWORD'];
    if (host == null || user == null || password == null) return null;

    return DirectDbConfig(
      host: host,
      port: int.tryParse(v['TIDB_PORT'] ?? '4000') ?? 4000,
      user: user,
      password: password,
      database: v['TIDB_DB'] ?? 'drais',
    );
  }

  /// Parses `KEY=VALUE` lines, ignoring blanks and `#` comments.
  static Map<String, String> _parse(String contents) {
    final Map<String, String> out = <String, String>{};
    for (final String rawLine in contents.split(RegExp(r'\r?\n'))) {
      final String line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final int eq = line.indexOf('=');
      if (eq <= 0) continue;

      final String key = line.substring(0, eq).trim();
      String value = line.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) out[key] = value;
    }
    return out;
  }

  /// Never includes the password.
  @override
  String toString() => 'DirectDbConfig($user@$host:$port/$database)';
}
