import 'package:dio/dio.dart';

import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/network/api_response.dart';

/// Translates transport and protocol errors into the domain's [Failure] types.
///
/// This is the **only** place in the app that knows `dio` exists at the error
/// level. Everything above it reasons about [Failure] alone, which is what
/// lets the transport be replaced without touching a repository.
///
/// ## Classification order
///
/// The server's `error.code` wins wherever it is present, because it is the
/// contract (`src/lib/apiResponse.ts`). HTTP status is the fallback for routes
/// that do not emit a code — and there are several. Only when both are absent
/// or unrecognised does the transport-level exception type decide.
abstract final class ErrorMapper {
  /// Maps a `dio` exception into a [Failure].
  static Failure fromDioException(DioException e) {
    final Map<String, Object?> context = <String, Object?>{
      'method': e.requestOptions.method,
      'path': e.requestOptions.path,
      if (e.requestOptions.extra['requestId'] != null)
        'requestId': e.requestOptions.extra['requestId'],
    };

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      // Raised when a response transformer exceeds its budget — for DRAIS this
      // means an unexpectedly enormous JSON body. Handled as a timeout because
      // the user-visible situation is identical: nothing arrived in time.
      case DioExceptionType.transformTimeout:
        return TimeoutFailure(
          technicalDetail: '${e.type.name}: ${e.message}',
          debugContext: context,
          cause: e,
          stackTrace: e.stackTrace,
        );

      case DioExceptionType.connectionError:
        return NetworkFailure(
          technicalDetail: e.message,
          debugContext: context,
          cause: e,
          stackTrace: e.stackTrace,
        );

      case DioExceptionType.cancel:
        return CancelledFailure(
          technicalDetail: e.message,
          debugContext: context,
          cause: e,
          stackTrace: e.stackTrace,
        );

      case DioExceptionType.badCertificate:
        return NetworkFailure(
          message:
              'Could not verify a secure connection to DRAIS. '
              'If you are on a school or public network, it may be '
              'intercepting traffic.',
          technicalDetail: e.message,
          debugContext: context,
          cause: e,
          stackTrace: e.stackTrace,
        );

      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        final Response<Object?>? response = e.response;
        if (response == null) {
          return UnknownFailure(
            technicalDetail: '${e.type.name}: ${e.message}',
            debugContext: context,
            cause: e,
            stackTrace: e.stackTrace,
          );
        }
        return fromResponse(
          response,
          context: context,
          cause: e,
          stackTrace: e.stackTrace,
        );
    }
  }

  /// Maps a completed HTTP response into a [Failure].
  ///
  /// Used both for `badResponse` exceptions and for 200-with-`success:false`
  /// bodies, which LongTerm does emit and which are unambiguously failures.
  static Failure fromResponse(
    Response<Object?> response, {
    Map<String, Object?> context = const <String, Object?>{},
    Object? cause,
    StackTrace? stackTrace,
  }) {
    final int status = response.statusCode ?? 0;
    final Object? body = response.data;

    if (body is! Map) {
      // Not JSON, or JSON that is not an object — an HTML proxy error page,
      // a captive portal, a gateway timeout page.
      return MalformedResponseFailure(
        technicalDetail: 'HTTP $status, body type ${body.runtimeType}',
        statusCode: status,
        debugContext: context,
        cause: cause,
        stackTrace: stackTrace,
      );
    }

    final Map<String, Object?> json = body.map(
      (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
    );
    final ApiEnvelope<void> envelope = ApiEnvelope.parse<void>(json);

    return fromEnvelope(
      envelope,
      statusCode: status,
      context: context,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  /// Maps a parsed envelope into a [Failure].
  static Failure fromEnvelope(
    ApiEnvelope<void> envelope, {
    required int statusCode,
    Map<String, Object?> context = const <String, Object?>{},
    Object? cause,
    StackTrace? stackTrace,
  }) {
    final ApiErrorCode code = envelope.errorCode ?? _codeFromStatus(statusCode);
    final String? serverMessage = envelope.errorMessage ?? envelope.message;
    final Map<String, Object?> ctx = <String, Object?>{
      ...context,
      'code': code.wireValue,
      'status': statusCode,
    };

    switch (code) {
      // ── 401 and credential failures ──────────────────────────────────
      case ApiErrorCode.unauthorized:
      case ApiErrorCode.sessionInvalid:
      case ApiErrorCode.sessionExpired:
      case ApiErrorCode.unauthorizedSchool:
      case ApiErrorCode.notAuthenticated:
        return AuthenticationFailure(
          code: code,
          message: 'Your session has ended. Please sign in again.',
          technicalDetail: serverMessage,
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      case ApiErrorCode.invalidCredentials:
      case ApiErrorCode.missingCredentials:
        return AuthenticationFailure(
          code: code,
          // Mirrors the server's deliberate ambiguity: never reveal whether
          // the email exists.
          message: serverMessage ?? 'Invalid email or password.',
          technicalDetail: serverMessage,
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      // ── 402 billing ──────────────────────────────────────────────────
      case ApiErrorCode.subscriptionExpired:
        return SubscriptionFailure(
          message:
              serverMessage ??
              'This school\'s DRAIS subscription has expired. '
                  'Please renew to restore access.',
          subscriptionStatus: _subscriptionStatus(envelope),
          expiresAt: _subscriptionExpiry(envelope),
          technicalDetail: serverMessage,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      // ── 403 authorization / account and tenant state ─────────────────
      case ApiErrorCode.forbidden:
      case ApiErrorCode.permissionDenied:
        return AuthorizationFailure(
          code: code,
          message:
              'You do not have permission to do this. '
              'Ask your school administrator if you need access.',
          technicalDetail: serverMessage,
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      case ApiErrorCode.setupIncomplete:
        return AuthorizationFailure(
          code: code,
          message:
              'School setup is not finished yet. '
              'An administrator must complete it on the web app first.',
          technicalDetail: serverMessage,
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      case ApiErrorCode.accountPending:
      case ApiErrorCode.accountInactive:
      case ApiErrorCode.schoolSuspended:
      case ApiErrorCode.schoolInactive:
        return AuthorizationFailure(
          code: code,
          // The server's wording here is specific and correct — it names the
          // remedy ("contact your administrator"), so we keep it.
          message: serverMessage ?? 'This account is not currently active.',
          technicalDetail: serverMessage,
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      // ── 400 validation ───────────────────────────────────────────────
      case ApiErrorCode.badRequest:
      case ApiErrorCode.invalidInput:
      case ApiErrorCode.missingField:
      case ApiErrorCode.invalidEmail:
      case ApiErrorCode.invalidPassword:
        return ValidationFailure(
          code: code,
          message: serverMessage ?? 'Please check the details you entered.',
          fieldErrors: _fieldErrors(envelope),
          technicalDetail: serverMessage,
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      // ── 404 ──────────────────────────────────────────────────────────
      case ApiErrorCode.notFound:
      case ApiErrorCode.userNotFound:
      case ApiErrorCode.schoolNotFound:
      case ApiErrorCode.resourceNotFound:
        return NotFoundFailure(
          code: code,
          message: serverMessage ?? 'That record could not be found.',
          technicalDetail: serverMessage,
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      // ── 409 ──────────────────────────────────────────────────────────
      case ApiErrorCode.conflict:
      case ApiErrorCode.duplicateEntry:
      case ApiErrorCode.emailAlreadyExists:
        return ConflictFailure(
          code: code,
          message: serverMessage ?? 'That record already exists.',
          technicalDetail: serverMessage,
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      // ── 5xx ──────────────────────────────────────────────────────────
      case ApiErrorCode.internalError:
      case ApiErrorCode.databaseError:
      case ApiErrorCode.serverError:
      case ApiErrorCode.logoutError:
        return ServerFailure(
          code: code,
          technicalDetail: serverMessage,
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );

      // ── Client-side codes never arrive from the server ───────────────
      case ApiErrorCode.offline:
      case ApiErrorCode.timeout:
      case ApiErrorCode.cancelled:
      case ApiErrorCode.malformedResponse:
      case ApiErrorCode.unknown:
        return UnknownFailure(
          message: serverMessage ?? 'Something went wrong. Please try again.',
          technicalDetail: serverMessage ?? 'Unclassified HTTP $statusCode',
          statusCode: statusCode,
          debugContext: ctx,
          cause: cause,
          stackTrace: stackTrace,
        );
    }
  }

  /// Fallback classification when the server sent no `error.code`.
  static ApiErrorCode _codeFromStatus(int status) => switch (status) {
    400 => ApiErrorCode.badRequest,
    401 => ApiErrorCode.unauthorized,
    402 => ApiErrorCode.subscriptionExpired,
    403 => ApiErrorCode.forbidden,
    404 => ApiErrorCode.notFound,
    409 => ApiErrorCode.conflict,
    422 => ApiErrorCode.invalidInput,
    >= 500 => ApiErrorCode.serverError,
    _ => ApiErrorCode.unknown,
  };

  /// Extracts field-level validation errors from `error.details`.
  ///
  /// LongTerm's `ApiErrorFactory.invalidInput()` writes `{ field: '<name>' }`,
  /// so the common case is one named field with the top-level message
  /// attached to it. Richer shapes (`{ field: ['msg', …] }`) are supported for
  /// when the backend grows them.
  static Map<String, List<String>> _fieldErrors(ApiEnvelope<void> envelope) {
    final Map<String, Object?>? details = envelope.errorDetails;
    if (details == null || details.isEmpty) {
      return const <String, List<String>>{};
    }

    final String fallback =
        envelope.errorMessage ?? envelope.message ?? 'Invalid value.';

    // Shape A: { field: 'email' }
    final Object? namedField = details['field'];
    if (namedField is String && details.length == 1) {
      return <String, List<String>>{
        namedField: <String>[fallback],
      };
    }

    // Shape B: { email: 'msg' } or { email: ['msg', ...] }
    final Map<String, List<String>> out = <String, List<String>>{};
    for (final MapEntry<String, Object?> entry in details.entries) {
      final Object? value = entry.value;
      if (value is String) {
        out[entry.key] = <String>[value];
      } else if (value is List) {
        out[entry.key] = value.map((Object? v) => '$v').toList(growable: false);
      }
    }
    return out;
  }

  /// Reads `subscription.status` / `subscriptionInfo.status` — `/api/auth/login`
  /// and `/api/auth/me` use different key names for the same object.
  static String? _subscriptionStatus(ApiEnvelope<void> envelope) {
    final Object? node =
        envelope['subscription'] ?? envelope['subscriptionInfo'];
    if (node is Map) return node['status'] as String?;
    return null;
  }

  static DateTime? _subscriptionExpiry(ApiEnvelope<void> envelope) {
    final Object? node =
        envelope['subscription'] ?? envelope['subscriptionInfo'];
    if (node is! Map) return null;
    final Object? raw = node['subscriptionEndDate'] ?? node['trialEndDate'];
    return raw is String ? DateTime.tryParse(raw) : null;
  }
}
