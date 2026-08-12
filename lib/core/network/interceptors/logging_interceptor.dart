import 'package:dio/dio.dart';

import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/logging/redaction.dart';

/// Logs the request/response lifecycle with production-safe redaction.
///
/// ## What is logged where
///
/// | | Development / staging / QA | Production |
/// |---|---|---|
/// | Method, path, status, duration | yes | yes |
/// | Request id | yes | yes |
/// | Request body | yes, redacted | **never** |
/// | Response body | yes, redacted, truncated | **never** |
/// | Headers | yes, redacted | **never** |
///
/// Production keeps enough to answer "which call failed, how, and how slowly"
/// and nothing that could carry a learner's name, a guardian's phone number,
/// or a session cookie into a crash report.
///
/// Every log line carries the `X-Request-Id` also sent to the server, so a
/// mobile failure can be joined to its row in LongTerm's `system_logs` table
/// (`src/lib/systemLogger.ts` records `requestId` on the same field).
class LoggingInterceptor extends Interceptor {
  /// Creates a logging interceptor.
  LoggingInterceptor({required AppLogger logger, required this.config})
    : _logger = logger.child('Http');

  final AppLogger _logger;

  /// Controls whether bodies may be logged at all.
  final AppConfig config;

  /// Longest response body fragment written to the log, in characters.
  static const int _maxBodyChars = 2000;

  /// Requests slower than this are logged at warn level. Chosen to be
  /// noticeable on a Ugandan 3G connection without crying wolf.
  static const Duration _slowThreshold = Duration(seconds: 5);

  static const String _startKey = 'drais.startedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now();

    if (!config.enableNetworkLogging) {
      handler.next(options);
      return;
    }

    _logger.debug(
      '→ ${options.method} ${options.path}',
      context: <String, Object?>{
        'requestId': options.extra['requestId'],
        if (options.queryParameters.isNotEmpty)
          'query': Redaction.scrubMap(options.queryParameters),
        if (config.environment.allowsDiagnostics && options.data != null)
          'body': _describeBody(options.data),
      },
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    final Duration elapsed = _elapsed(response.requestOptions);
    final String line =
        '← ${response.statusCode} ${response.requestOptions.method} '
        '${response.requestOptions.path} (${elapsed.inMilliseconds}ms)';

    final Map<String, Object?> context = <String, Object?>{
      'requestId': response.requestOptions.extra['requestId'],
      'status': response.statusCode,
      'ms': elapsed.inMilliseconds,
    };

    if (elapsed > _slowThreshold) {
      _logger.warn('$line — slow', context: context);
    } else if (config.enableNetworkLogging) {
      _logger.debug(
        line,
        context: <String, Object?>{
          ...context,
          if (config.environment.allowsDiagnostics)
            'body': _describeBody(response.data),
        },
      );
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final Duration elapsed = _elapsed(err.requestOptions);

    // Failures are logged in production too — an error with no record is the
    // silent failure the whole standard exists to prevent.
    _logger.error(
      '✖ ${err.type.name} ${err.requestOptions.method} '
      '${err.requestOptions.path} (${elapsed.inMilliseconds}ms)',
      error: err.error ?? err.message,
      stackTrace: err.stackTrace,
      context: <String, Object?>{
        'requestId': err.requestOptions.extra['requestId'],
        'status': err.response?.statusCode,
        'ms': elapsed.inMilliseconds,
        if (config.environment.allowsDiagnostics && err.response != null)
          'body': _describeBody(err.response?.data),
      },
    );

    handler.next(err);
  }

  Duration _elapsed(RequestOptions options) {
    final Object? startedAt = options.extra[_startKey];
    if (startedAt is! DateTime) return Duration.zero;
    return DateTime.now().difference(startedAt);
  }

  /// Renders a body for the log: redacted, truncated, and never binary.
  static String _describeBody(Object? body) {
    if (body == null) return 'null';
    if (body is FormData) {
      // Multipart bodies contain file bytes — describe, never dump.
      final Iterable<String> fields = body.fields.map(
        (MapEntry<String, String> f) => f.key,
      );
      final Iterable<String> files = body.files.map(
        (MapEntry<String, MultipartFile> f) => f.key,
      );
      return 'FormData(fields: [${fields.join(', ')}], '
          'files: [${files.join(', ')}])';
    }
    if (body is List<int>) return 'bytes(${body.length})';

    final String text = Redaction.scrubText(body.toString());
    return text.length <= _maxBodyChars
        ? text
        : '${text.substring(0, _maxBodyChars)}… (${text.length} chars)';
  }
}
