import 'dart:async';

import 'package:dio/dio.dart';

import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/network/api_response.dart';

/// Detects a dead session on any response and raises it once, globally.
///
/// ## Why there is no token refresh
///
/// The canonical shape of this interceptor in most Flutter apps is
/// "on 401, call `/refresh`, replay the request". DRAIS has no such endpoint.
/// School authentication is an opaque server-side session row
/// (`sessions.session_token`, seven-day `expires_at`) validated by
/// `getSessionSchoolId()`. There is no refresh token, no sliding renewal, and
/// no rotation — `sessions.last_activity_at` is updated on each request but
/// does **not** extend `expires_at`.
///
/// So when the session dies, it is dead. The only recovery is a new sign-in.
/// This interceptor makes that a single, orderly event rather than a dozen
/// screens each showing their own error.
///
/// The seam is real, though: [onSessionInvalidated] is the exact place a
/// refresh would be attempted if LongTerm ever grows one. See
/// `docs/adr/M0002-cookie-session-parity.md` for the conditions that would
/// justify adding one server-side.
///
/// ## Why 200-with-`success:false` is inspected
///
/// Several LongTerm routes return HTTP 200 with `{ success: false }`. Watching
/// only for status 401 would miss those, and the app would render an empty
/// screen instead of returning the user to the login page.
class SessionInterceptor extends Interceptor {
  /// Creates a session interceptor.
  ///
  /// [onSessionInvalidated] is invoked at most once per dead session; the
  /// guard resets after [reset] is called by the auth controller once the user
  /// has signed in again.
  SessionInterceptor({
    required Future<void> Function(ApiErrorCode code) onSessionInvalidated,
    required AppLogger logger,
  }) : _onSessionInvalidated = onSessionInvalidated,
       _logger = logger.child('Session');

  final Future<void> Function(ApiErrorCode code) _onSessionInvalidated;
  final AppLogger _logger;

  /// Guards against a burst of parallel requests each triggering sign-out.
  bool _handling = false;

  /// Paths where a 401 is an expected outcome rather than an expired session.
  ///
  /// A failed login must not be reported as "your session ended" — the user
  /// never had one.
  static const Set<String> _exemptPaths = <String>{
    '/api/auth/login',
    '/api/auth/logout',
    '/api/auth/signup',
    '/api/auth/impersonation-status',
  };

  /// Re-arms the interceptor after a successful sign-in.
  void reset() => _handling = false;

  @override
  Future<void> onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) async {
    final Object? body = response.data;
    if (body is Map && !_isExempt(response.requestOptions.path)) {
      final ApiEnvelope<void> envelope = ApiEnvelope.parse<void>(
        body.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v)),
      );
      final ApiErrorCode? code = envelope.errorCode;
      if (envelope.isFailure && code != null && code.requiresReauthentication) {
        await _invalidate(code, response.requestOptions);
      }
    }
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_isExempt(err.requestOptions.path)) {
      handler.next(err);
      return;
    }

    final int? status = err.response?.statusCode;
    ApiErrorCode code = ApiErrorCode.unknown;

    final Object? body = err.response?.data;
    if (body is Map) {
      code =
          ApiEnvelope.parse<void>(
            body.map(
              (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
            ),
          ).errorCode ??
          ApiErrorCode.unknown;
    }

    // Status is the fallback: a 401 with no parseable body is still a dead
    // session, and middleware.ts can return one before any route runs.
    if (code.requiresReauthentication || status == 401) {
      await _invalidate(
        code.requiresReauthentication ? code : ApiErrorCode.sessionExpired,
        err.requestOptions,
      );
    }

    handler.next(err);
  }

  Future<void> _invalidate(ApiErrorCode code, RequestOptions request) async {
    if (_handling) return;
    _handling = true;

    _logger.warn(
      'Session invalidated — signing out.',
      context: <String, Object?>{
        'code': code.wireValue,
        'path': request.path,
        'requestId': request.extra['requestId'],
      },
    );

    try {
      await _onSessionInvalidated(code);
    } on Object catch (e, s) {
      // Sign-out must never throw into the interceptor chain: doing so would
      // replace the user's real error with an unrelated one.
      _logger.error('Sign-out handler failed.', error: e, stackTrace: s);
    }
  }

  static bool _isExempt(String path) =>
      _exemptPaths.any((String exempt) => path.startsWith(exempt));
}
