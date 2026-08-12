/// The DRAIS response envelope, mirrored from `src/lib/apiResponse.ts`.
///
/// ## Three shapes, one parser
///
/// LongTerm emits the envelope in three variants, all of which reach clients:
///
/// 1. `{ success: true, data: T }` — `createSuccessResponse()`.
/// 2. `{ success: true, message: string, data?: T }` — the `ok()` shorthand,
///    described in the source as "MANDATORY for all new/updated routes".
/// 3. Flat payloads with `success` alongside domain keys — `/api/auth/login`
///    returns `{ success, user, setupComplete, mustChangePassword }`, and
///    `/api/auth/me` returns `{ success, user, setupComplete }`.
///
/// The web client absorbs this with `data?.data || data` in `apiClient.ts`.
/// Rather than repeat that guesswork at every call site, [ApiEnvelope] parses
/// all three and exposes one shape. Where a route uses variant 3, the caller
/// passes an explicit `dataKey` — see [ApiEnvelope.parse].
///
/// The three-shape split is recorded as backend technical debt in
/// `docs/PARITY.md`; if LongTerm ever consolidates on one, this parser keeps
/// working unchanged.
library;

import 'package:drais/core/error/api_error_code.dart';

/// A parsed DRAIS API envelope.
class ApiEnvelope<T> {
  /// Creates an envelope.
  const ApiEnvelope({
    required this.success,
    this.data,
    this.message,
    this.errorCode,
    this.errorMessage,
    this.errorDetails,
    this.raw = const <String, Object?>{},
  });

  /// The server's `success` flag. **Authoritative.**
  ///
  /// A 200 response with `success: false` is a failure — several LongTerm
  /// routes do exactly this, so status code alone is not enough.
  final bool success;

  /// The decoded payload, when the caller asked for one.
  final T? data;

  /// Human-readable message from `ok()`/`fail()`. Suitable for a toast.
  final String? message;

  /// Machine-readable error identity.
  final ApiErrorCode? errorCode;

  /// The server's error message. Logged; shown only when we have nothing
  /// better, because these strings are English-only and change freely.
  final String? errorMessage;

  /// `error.details` — field-level validation info, when present.
  final Map<String, Object?>? errorDetails;

  /// The full decoded body, retained so that flat-shaped responses (variant 3)
  /// and out-of-envelope keys such as `subscription` and `warning` remain
  /// reachable without another round of parsing.
  final Map<String, Object?> raw;

  /// Whether the envelope reports failure.
  bool get isFailure => !success;

  /// Reads an arbitrary top-level key from the raw body.
  Object? operator [](String key) => raw[key];

  /// Parses a decoded JSON body into an envelope.
  ///
  /// [fromJson] converts the payload; [dataKey] names the top-level key the
  /// payload lives under for flat-shaped routes (`'user'` for `/api/auth/me`).
  /// When [dataKey] is omitted, `data` is used, and if that is absent the
  /// whole body is passed to [fromJson] — which is what routes returning a
  /// bare object need.
  static ApiEnvelope<T> parse<T>(
    Map<String, Object?> body, {
    T Function(Object json)? fromJson,
    String? dataKey,
  }) {
    // Absent `success` is treated as success: a handful of legacy routes
    // return a bare payload with no flag, and a 2xx with a body is a success
    // by HTTP's own definition.
    final bool success = body['success'] as bool? ?? true;

    final Object? errorNode = body['error'];
    ApiErrorCode? code;
    String? errorMessage;
    Map<String, Object?>? details;

    if (errorNode is Map) {
      final Map<String, Object?> error = errorNode.map(
        (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
      );
      code = ApiErrorCode.fromWire(error['code'] as String?);
      errorMessage = error['message'] as String?;
      final Object? rawDetails = error['details'];
      if (rawDetails is Map) {
        details = rawDetails.map(
          (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
        );
      }
    } else if (errorNode is String) {
      // `fail()` puts an arbitrary value in `error`; some routes put a string.
      errorMessage = errorNode;
    }

    // `fail()` reports its message at the top level, not inside `error`.
    final String? message = body['message'] as String?;
    if (!success && errorMessage == null) errorMessage = message;

    T? data;
    if (fromJson != null) {
      final Object? payload = _extractPayload(body, dataKey);
      if (payload != null) data = fromJson(payload);
    }

    return ApiEnvelope<T>(
      success: success,
      data: data,
      message: message,
      errorCode: code,
      errorMessage: errorMessage,
      errorDetails: details,
      raw: body,
    );
  }

  static Object? _extractPayload(Map<String, Object?> body, String? dataKey) {
    if (dataKey != null) return body[dataKey];
    if (body.containsKey('data')) return body['data'];
    return body;
  }

  @override
  String toString() =>
      'ApiEnvelope(success: $success, '
      'code: ${errorCode?.wireValue}, message: ${message ?? errorMessage})';
}
