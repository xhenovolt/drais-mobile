import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/network/network_info.dart';

/// Retries requests that failed for reasons a retry can plausibly fix.
///
/// ## What is retried, and what is never retried
///
/// Retrying is only safe when re-running the request cannot double an effect.
/// That is a property of the *method*, not of the error:
///
/// * **Retried:** `GET`, `HEAD`, `OPTIONS` — idempotent by HTTP's definition.
/// * **Never retried:** `POST`, `PUT`, `PATCH`, `DELETE`.
///
/// The `PUT`/`DELETE` exclusion is stricter than HTTP requires. It is
/// deliberate: DRAIS routes are not uniformly idempotent in practice — several
/// write audit rows, send guardian SMS through Africa's Talking, or increment
/// counters — so a retried `PUT` can bill a school for two messages. The
/// backend has no idempotency-key mechanism on internal routes (only the
/// Platform API has one, per ADR-0011), so the client cannot make this safe
/// on its own. Until it can, we do not try.
///
/// ## Which failures
///
/// Connection errors, timeouts, and 5xx responses — states that are usually
/// transient on an intermittent connection. A 4xx is never retried: the
/// request was wrong and will be wrong again.
///
/// ## Backoff
///
/// Exponential with jitter. Jitter matters here: a school's staff all lose
/// connectivity at the same moment and reconnect at the same moment, and a
/// fixed backoff would turn that into a synchronised stampede against a
/// single-region TiDB deployment.
class RetryInterceptor extends Interceptor {
  /// Creates a retry interceptor.
  RetryInterceptor({
    required this.maxRetries,
    required NetworkInfo networkInfo,
    required AppLogger logger,
    this.baseDelay = const Duration(milliseconds: 400),
  }) : _networkInfo = networkInfo,
       _logger = logger.child('Retry');

  /// Maximum additional attempts after the first.
  final int maxRetries;

  /// First backoff interval; doubles each attempt.
  final Duration baseDelay;

  final NetworkInfo _networkInfo;
  final AppLogger _logger;
  final math.Random _random = math.Random();

  static const String _attemptKey = 'drais.retryAttempt';

  /// Methods safe to repeat. See the class docs for why writes are excluded.
  static const Set<String> _retryableMethods = <String>{
    'GET',
    'HEAD',
    'OPTIONS',
  };

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions request = err.requestOptions;
    final int attempt = (request.extra[_attemptKey] as int?) ?? 0;

    if (!_shouldRetry(err, attempt)) {
      handler.next(err);
      return;
    }

    // No point burning the retry budget while the radio is off — but do not
    // fail either: connectivity can return within the backoff window.
    final bool online = await _networkInfo.isConnected;
    if (!online) {
      _logger.debug(
        'Device offline; not retrying.',
        context: <String, Object?>{'path': request.path},
      );
      handler.next(err);
      return;
    }

    final Duration delay = _backoffFor(attempt);
    _logger.info(
      'Retrying ${request.method} ${request.path}',
      context: <String, Object?>{
        'attempt': attempt + 1,
        'of': maxRetries,
        'afterMs': delay.inMilliseconds,
        'reason': err.type.name,
        'requestId': request.extra['requestId'],
      },
    );

    await Future<void>.delayed(delay);

    try {
      final Response<Object?> response = await Dio(
        BaseOptions(
          baseUrl: request.baseUrl,
          connectTimeout: request.connectTimeout,
          receiveTimeout: request.receiveTimeout,
          sendTimeout: request.sendTimeout,
        ),
      ).fetch<Object?>(request..extra[_attemptKey] = attempt + 1);
      handler.resolve(response);
    } on DioException catch (retryError) {
      // Hand the *retry's* error onward so the failure the user sees reflects
      // the last real attempt, not the first.
      handler.next(retryError);
    }
  }

  bool _shouldRetry(DioException err, int attempt) {
    if (attempt >= maxRetries) return false;
    if (!_retryableMethods.contains(err.requestOptions.method.toUpperCase())) {
      return false;
    }
    // An explicit opt-out for callers that manage their own retry semantics.
    if (err.requestOptions.extra['noRetry'] == true) return false;

    switch (err.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
        return true;
      case DioExceptionType.badResponse:
        final int status = err.response?.statusCode ?? 0;
        // 5xx only. 502/503/504 in particular are what a cold serverless
        // function or a saturated connection pool looks like.
        return status >= 500;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return false;
    }
  }

  /// Exponential backoff with full jitter, capped at 8 seconds.
  Duration _backoffFor(int attempt) {
    final int ceiling = baseDelay.inMilliseconds * (1 << attempt);
    final int capped = math.min(ceiling, 8000);
    return Duration(
      milliseconds: capped ~/ 2 + _random.nextInt(capped ~/ 2 + 1),
    );
  }
}
