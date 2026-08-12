import 'package:mysql_client/mysql_client.dart';

import 'package:drais/core/config/data_mode.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/logging/app_logger.dart';

/// One database row.
typedef Row = Map<String, Object?>;

/// In-process TiDB Cloud access, for [DataMode.direct].
///
/// The app becomes its own backend: it opens the connection and runs the
/// queries, with no HTTP layer in between. This is the same shape as the
/// Next.js desktop build, where the API routes execute inside the executable.
///
/// ## What changes when there is no server
///
/// Two guarantees that a server provides for free now have to be provided
/// here, deliberately and visibly:
///
/// * **Tenant scope.** `school_id` must come from the validated session row,
///   never from anything the UI holds. Every query in `direct/` follows the
///   same rule the server does, for the same reason.
/// * **Authorization.** Permission checks are the app's own. On a device the
///   operator controls this is acceptable; on a device they do not, it is not
///   a boundary at all — see the warning in `docs/DEPLOYMENT_MODES.md`.
///
/// ## The TiDB quirk, again
///
/// TiDB rejects `LIMIT ?` / `OFFSET ?` under the prepared-statement protocol
/// (ADR-0010). [query] throws on such a statement so it fails during
/// development rather than only in production; use [limitClause].
class DraisDatabase {
  DraisDatabase._(this._pool, this._logger);

  final MySQLConnectionPool _pool;
  final AppLogger _logger;

  /// Opens the pool. TLS is mandatory — TiDB Cloud requires it, and a
  /// cleartext connection over the public internet would expose every query.
  static DraisDatabase open(DirectDbConfig config, AppLogger logger) {
    final MySQLConnectionPool pool = MySQLConnectionPool(
      host: config.host,
      port: config.port,
      userName: config.user,
      password: config.password,
      databaseName: config.database,
      // Small on purpose: TiDB Cloud caps concurrent connections, and in this
      // mode every installed copy of the app holds its own pool.
      maxConnections: 2,
      secure: true,
    );
    return DraisDatabase._(pool, logger.child('Db'));
  }

  /// Runs a query and returns its rows.
  ///
  /// Failures arrive as a [Failure], like everything else the app can go wrong
  /// with, so a screen handles a database error exactly as it handles an HTTP
  /// one and nothing above `data/` learns that SQL exists.
  Future<List<Row>> query(
    String sql, [
    List<Object?> params = const <Object?>[],
  ]) async {
    _assertNoBoundLimit(sql);

    try {
      final IResultSet result = params.isEmpty
          ? await _pool.execute(sql)
          : await _pool.execute(_toNamed(sql), _bind(params));
      return result.rows
          .map((ResultSetRow row) => row.typedAssoc())
          .toList(growable: false);
    } on Object catch (e, s) {
      throw _asFailure(e, s);
    }
  }

  /// Runs a query expected to return at most one row.
  Future<Row?> queryOne(
    String sql, [
    List<Object?> params = const <Object?>[],
  ]) async {
    final List<Row> rows = await query(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  /// Runs a statement, returning the affected row count.
  Future<int> execute(
    String sql, [
    List<Object?> params = const <Object?>[],
  ]) async {
    _assertNoBoundLimit(sql);

    try {
      final IResultSet result = params.isEmpty
          ? await _pool.execute(sql)
          : await _pool.execute(_toNamed(sql), _bind(params));
      return result.affectedRows.toInt();
    } on Object catch (e, s) {
      throw _asFailure(e, s);
    }
  }

  /// Connectivity probe, used by the diagnostics screen.
  Future<({bool connected, int? latencyMs, String? error})> ping() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      await _pool.execute('SELECT 1 AS ok');
      return (
        connected: true,
        latencyMs: stopwatch.elapsedMilliseconds,
        error: null,
      );
    } on Object catch (e) {
      return (connected: false, latencyMs: null, error: _scrub(e.toString()));
    }
  }

  /// Closes the pool.
  Future<void> close() async {
    try {
      await _pool.close();
    } on Object catch (e) {
      _logger.warn(
        'Error closing the database pool.',
        context: <String, Object?>{'reason': e.runtimeType},
      );
    }
  }

  /// The only sanctioned way to paginate. Values are clamped integers, so
  /// nothing user-supplied reaches the statement as text.
  static String limitClause({required int limit, int offset = 0}) {
    final int safeLimit = limit.clamp(1, 500);
    final int safeOffset = offset < 0 ? 0 : offset;
    return 'LIMIT $safeLimit OFFSET $safeOffset';
  }

  /// Maps a driver error onto the app's failure vocabulary.
  ///
  /// A dropped connection is a [NetworkFailure] — the same thing a failed HTTP
  /// request would produce — so the UI shows "check your connection" rather
  /// than a MySQL error string. Everything else is a [ServerFailure]: in this
  /// mode the database *is* the server.
  Failure _asFailure(Object error, StackTrace stackTrace) {
    final String detail = _scrub(error.toString());
    final String lower = detail.toLowerCase();

    final bool looksLikeConnectivity =
        lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('timed out') ||
        lower.contains('host lookup') ||
        lower.contains('closed');

    _logger.error(
      'Database operation failed.',
      error: detail,
      stackTrace: stackTrace,
    );

    if (looksLikeConnectivity) {
      return NetworkFailure(
        message: 'Could not reach the DRAIS database. Check your connection.',
        technicalDetail: detail,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return ServerFailure(
      message: 'Something went wrong reading DRAIS data.',
      technicalDetail: detail,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// Removes anything credential-shaped before an error is logged or shown.
  static String _scrub(String raw) {
    final String masked = raw.replaceAll(
      RegExp(r'(password|user)\s*[=:]\s*[^\s,;)]+', caseSensitive: false),
      r'$1=***',
    );
    return masked.length > 300 ? masked.substring(0, 300) : masked;
  }

  static Map<String, Object?> _bind(List<Object?> params) {
    final Map<String, Object?> out = <String, Object?>{};
    for (int i = 0; i < params.length; i++) {
      out['p$i'] = params[i];
    }
    return out;
  }

  /// Converts `?` markers to the `:pN` form the driver expects, skipping
  /// question marks inside string literals.
  static String _toNamed(String sql) {
    final StringBuffer out = StringBuffer();
    int index = 0;
    bool inString = false;

    for (int i = 0; i < sql.length; i++) {
      final String char = sql[i];
      if (char == "'" && (i == 0 || sql[i - 1] != r'\')) {
        inString = !inString;
        out.write(char);
      } else if (char == '?' && !inString) {
        out.write(':p${index++}');
      } else {
        out.write(char);
      }
    }
    return out.toString();
  }

  static final RegExp _boundLimit = RegExp(
    r'\b(limit|offset)\s+\?',
    caseSensitive: false,
  );

  static void _assertNoBoundLimit(String sql) {
    if (_boundLimit.hasMatch(sql)) {
      throw ArgumentError(
        'TiDB rejects bound LIMIT/OFFSET under the prepared-statement '
        'protocol. Use DraisDatabase.limitClause() — see ADR-0010.',
      );
    }
  }
}

/// Coercion helpers shared by the direct-mode data sources.
///
/// The driver returns `BIGINT` as `int` or `String` depending on the path, and
/// `TINYINT(1)` as `0`/`1` rather than a bool, so every read coerces rather
/// than casts.
abstract final class SqlValue {
  /// Reads an integer.
  static int? asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Reads a boolean.
  static bool asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String v = value.trim().toLowerCase();
      return v == '1' || v == 'true';
    }
    return false;
  }

  /// Reads a string.
  static String? asString(Object? value) => value?.toString();

  /// Reads a date.
  static DateTime? asDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
