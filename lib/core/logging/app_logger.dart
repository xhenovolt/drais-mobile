import 'dart:developer' as developer;

import 'package:drais/core/config/environment.dart';
import 'package:drais/core/logging/redaction.dart';

/// Severity levels, mirroring `LogLevel` in `src/lib/systemLogger.ts` so that
/// mobile and server logs read as one stream when correlated by `requestId`.
enum LogLevel {
  /// Fine-grained tracing. Development only.
  debug(0, 'DEBUG'),

  /// Normal lifecycle events: navigation, sign-in, cache hits.
  info(1, 'INFO'),

  /// Something unexpected that the app recovered from.
  warn(2, 'WARN'),

  /// An operation failed. Always carries a [Failure] or exception.
  error(3, 'ERROR');

  const LogLevel(this.severity, this.label);

  /// Ordinal used for threshold comparisons.
  final int severity;

  /// Fixed-width label used in log output.
  final String label;
}

/// Structured application logger.
///
/// ## Why not `print`
///
/// `print` has no level, no source, no redaction, and ships to production. The
/// lint config makes it an error. Everything goes through here.
///
/// ## Production safety
///
/// The rule is the same as the backend's: **diagnostics are for engineers,
/// never for attackers.** In production this logger
///
/// * drops `debug` entirely,
/// * never emits request or response bodies,
/// * passes every message and context map through [Redaction], which strips
///   session cookies, passwords, tokens and bearer headers.
///
/// A log line that would leak a `drais_session` value is a security incident,
/// so redaction is applied unconditionally — in development too, where it
/// would otherwise be tempting to switch off and then forget.
class AppLogger {
  /// Creates a logger for [source], typically the class or subsystem name.
  const AppLogger(this.source, {required this.environment});

  /// Creates a child logger for a nested source (`Api` → `Api.Auth`).
  AppLogger child(String suffix) =>
      AppLogger('$source.$suffix', environment: environment);

  /// Where the log came from — mirrors `system_logs.source`.
  final String source;

  /// Controls verbosity and diagnostic exposure.
  final Environment environment;

  /// The lowest level emitted in the current environment.
  LogLevel get threshold =>
      environment.isProduction ? LogLevel.info : LogLevel.debug;

  /// Logs a debug message. No-op in production.
  void debug(String message, {Map<String, Object?>? context}) =>
      _write(LogLevel.debug, message, context: context);

  /// Logs a normal lifecycle event.
  void info(String message, {Map<String, Object?>? context}) =>
      _write(LogLevel.info, message, context: context);

  /// Logs a recovered-from anomaly.
  void warn(String message, {Map<String, Object?>? context}) =>
      _write(LogLevel.warn, message, context: context);

  /// Logs a failure. [error] and [stackTrace] are always retained.
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) => _write(
    LogLevel.error,
    message,
    context: context,
    error: error,
    stackTrace: stackTrace,
  );

  void _write(
    LogLevel level,
    String message, {
    Map<String, Object?>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.severity < threshold.severity) return;

    final String safeMessage = Redaction.scrubText(message);
    final Map<String, Object?> safeContext = context == null
        ? const <String, Object?>{}
        : Redaction.scrubMap(context);

    final StringBuffer line = StringBuffer()
      ..write('[${level.label}] ')
      ..write('[$source] ')
      ..write(safeMessage);

    if (safeContext.isNotEmpty) {
      line.write(' ${_formatContext(safeContext)}');
    }

    // `dart:developer` keeps levels, timestamps and stack traces intact in
    // DevTools and is stripped of console noise in release builds.
    developer.log(
      line.toString(),
      name: 'DRAIS',
      level: _developerLevel(level),
      time: DateTime.now(),
      error: error == null ? null : Redaction.scrubText(error.toString()),
      // A stack trace names our own files, not user data — safe to retain
      // in production, where it is the only forensic evidence we will get.
      stackTrace: stackTrace,
    );
  }

  static String _formatContext(Map<String, Object?> context) {
    final Iterable<String> pairs = context.entries.map(
      (MapEntry<String, Object?> e) => '${e.key}=${e.value}',
    );
    return '{${pairs.join(', ')}}';
  }

  /// Maps to the `package:logging` levels `dart:developer` expects.
  static int _developerLevel(LogLevel level) => switch (level) {
    LogLevel.debug => 500,
    LogLevel.info => 800,
    LogLevel.warn => 900,
    LogLevel.error => 1000,
  };
}
