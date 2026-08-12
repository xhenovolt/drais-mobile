import 'dart:convert';

import 'package:shelf/shelf.dart';

/// The DRAIS response envelope and error vocabulary.
///
/// Mirrors `src/lib/apiResponse.ts` from DRAIS LongTerm, because the Flutter
/// client already speaks that contract and must work against this server with
/// **no code change**. That is the whole test of this exercise: if the client
/// needs modifying, the contract has drifted.
///
/// The codes below include both families the platform emits — the canonical
/// `ApiErrorCode` enum, and the extra codes the hand-written auth routes
/// produce (`INVALID_CREDENTIALS`, `ACCOUNT_PENDING`, …). See
/// `../../docs/PARITY.md` §3.1: this implementation reproduces both, because
/// clients in the field already handle them.
abstract final class ApiErrorCode {
  // Authentication (401)
  static const String unauthorized = 'UNAUTHORIZED';
  static const String sessionInvalid = 'SESSION_INVALID';
  static const String sessionExpired = 'SESSION_EXPIRED';
  static const String notAuthenticated = 'NOT_AUTHENTICATED';
  static const String invalidCredentials = 'INVALID_CREDENTIALS';

  // Authorization (403)
  static const String forbidden = 'FORBIDDEN';
  static const String permissionDenied = 'PERMISSION_DENIED';
  static const String setupIncomplete = 'SETUP_INCOMPLETE';
  static const String accountPending = 'ACCOUNT_PENDING';
  static const String accountInactive = 'ACCOUNT_INACTIVE';
  static const String schoolSuspended = 'SCHOOL_SUSPENDED';
  static const String schoolInactive = 'SCHOOL_INACTIVE';

  // Billing (402)
  static const String subscriptionExpired = 'SUBSCRIPTION_EXPIRED';

  // Validation (400)
  static const String badRequest = 'BAD_REQUEST';
  static const String invalidInput = 'INVALID_INPUT';
  static const String missingCredentials = 'MISSING_CREDENTIALS';
  static const String missingField = 'MISSING_FIELD';

  // Not found (404)
  static const String notFound = 'NOT_FOUND';

  // Conflict (409)
  static const String conflict = 'CONFLICT';
  static const String duplicateEntry = 'DUPLICATE_ENTRY';

  // Server (5xx)
  static const String internalError = 'INTERNAL_ERROR';
  static const String databaseError = 'DATABASE_ERROR';
  static const String serverError = 'SERVER_ERROR';
}

/// Builders for the DRAIS response envelope.
abstract final class ApiResponse {
  static const Map<String, String> _jsonHeaders = <String, String>{
    'content-type': 'application/json; charset=utf-8',
    // No client should cache an authenticated response — a shared proxy
    // serving one user's identity to another is a tenant-isolation failure
    // that no amount of server-side scoping can prevent.
    'cache-control': 'no-store',
  };

  /// A success envelope: `{ success: true, ...payload }`.
  ///
  /// Payload keys sit at the top level rather than under `data`, matching the
  /// shape `/api/auth/login` and `/api/auth/me` already use. The client reads
  /// them with an explicit `dataKey`.
  static Response ok(
    Map<String, Object?> payload, {
    int status = 200,
    Map<String, String> headers = const <String, String>{},
  }) =>
      Response(
        status,
        body: jsonEncode(<String, Object?>{'success': true, ...payload}),
        headers: <String, String>{..._jsonHeaders, ...headers},
      );

  /// An error envelope: `{ success: false, error: { code, message } }`.
  ///
  /// [message] is shown to users, so it must be plain and actionable. Never
  /// put an exception string here — that is what the server log is for.
  static Response error(
    String code,
    String message, {
    required int status,
    Map<String, Object?>? details,
    Map<String, Object?> extra = const <String, Object?>{},
    Map<String, String> headers = const <String, String>{},
  }) =>
      Response(
        status,
        body: jsonEncode(<String, Object?>{
          'success': false,
          'error': <String, Object?>{
            'code': code,
            'message': message,
            if (details != null) 'details': details,
          },
          ...extra,
        }),
        headers: <String, String>{..._jsonHeaders, ...headers},
      );

  /// 401 — no valid session.
  static Response unauthorized([
    String message = 'Not authenticated',
    String code = ApiErrorCode.notAuthenticated,
  ]) =>
      error(code, message, status: 401);

  /// 400 — the request was malformed.
  static Response badRequest(
    String message, {
    String code = ApiErrorCode.badRequest,
    Map<String, Object?>? details,
  }) =>
      error(code, message, status: 400, details: details);

  /// 403 — authenticated but not permitted.
  static Response forbidden(
    String message, {
    String code = ApiErrorCode.forbidden,
  }) =>
      error(code, message, status: 403);

  /// 500 — unhandled server failure.
  ///
  /// The message is deliberately generic. Detail goes to the log, never to
  /// the client: a stack trace or SQL fragment in a response body tells an
  /// attacker about the schema.
  static Response serverError([
    String message = 'An unexpected error occurred',
  ]) =>
      error(ApiErrorCode.serverError, message, status: 500);
}
