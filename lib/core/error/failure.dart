import 'package:drais/core/error/api_error_code.dart';

/// The single error type crossing the data → domain → presentation boundary.
///
/// Everything that can go wrong — a socket that never opened, a 403 from RBAC,
/// a proxy returning HTML — arrives at the UI as one of the subtypes below.
/// No layer above `data/` ever sees a `DioException`, a `SocketException`, or
/// a raw status code.
///
/// A [Failure] carries **two audiences at once**:
///
/// * [message] — safe to show a user. Plain, actionable, never technical.
/// * [technicalDetail] / [debugContext] — for the log and the diagnostics
///   screen. Never rendered in production UI.
///
/// This is the mobile expression of the "zero silent failures" standard in
/// `docs/guides/API_ERROR_HANDLING_GUIDE.md`.
sealed class Failure implements Exception {
  /// Creates a failure.
  const Failure({
    required this.code,
    required this.message,
    this.technicalDetail,
    this.statusCode,
    this.debugContext = const <String, Object?>{},
    this.cause,
    this.stackTrace,
  });

  /// The machine-readable identity. Branch on this, never on [message].
  final ApiErrorCode code;

  /// User-facing text. Already plain language; render it as-is.
  final String message;

  /// Engineer-facing detail: the raw server message, exception string, or SQL
  /// state. Logged always, displayed only outside production.
  final String? technicalDetail;

  /// HTTP status, when the failure originated from a response.
  final int? statusCode;

  /// Structured context for logs — request path, field names, ids. Must never
  /// contain a password, session token or cookie.
  final Map<String, Object?> debugContext;

  /// The originating exception, retained for the log.
  final Object? cause;

  /// Stack trace at the point of origin.
  final StackTrace? stackTrace;

  /// Whether retrying the same operation is worth offering to the user.
  bool get isRetryable => code.isRetryable;

  /// Whether this failure invalidates the local session.
  bool get requiresReauthentication => code.requiresReauthentication;

  @override
  String toString() =>
      '$runtimeType(${code.wireValue}${statusCode != null ? ' HTTP $statusCode' : ''}): '
      '$message${technicalDetail != null ? ' — $technicalDetail' : ''}';
}

/// The device could not reach the server: no connectivity, DNS failure, or a
/// refused connection. **The request definitively did not run.**
final class NetworkFailure extends Failure {
  /// Creates a network failure.
  const NetworkFailure({
    super.code = ApiErrorCode.offline,
    super.message = 'No connection. Check your network and try again.',
    super.technicalDetail,
    super.debugContext,
    super.cause,
    super.stackTrace,
  });
}

/// A request exceeded its timeout.
///
/// Distinct from [NetworkFailure] because the outcome is *unknown*: a write
/// may well have been applied server-side. Never auto-retry a non-idempotent
/// request on this failure.
final class TimeoutFailure extends Failure {
  /// Creates a timeout failure.
  const TimeoutFailure({
    super.message = 'The server took too long to respond. Please try again.',
    super.technicalDetail,
    super.debugContext,
    super.cause,
    super.stackTrace,
  }) : super(code: ApiErrorCode.timeout);
}

/// The request was rejected because the caller is not authenticated (401), or
/// the credentials supplied were wrong.
///
/// [requiresReauthentication] distinguishes "your session died" (sign out and
/// return to login) from "you typed the wrong password" (stay on the form).
final class AuthenticationFailure extends Failure {
  /// Creates an authentication failure.
  const AuthenticationFailure({
    required super.code,
    required super.message,
    super.technicalDetail,
    super.statusCode = 401,
    super.debugContext,
    super.cause,
    super.stackTrace,
  });
}

/// The caller is authenticated but not permitted (403).
///
/// Raised by the backend's `requirePermission()` gate, by the account/school
/// status checks, and by the setup-incomplete gate.
final class AuthorizationFailure extends Failure {
  /// Creates an authorization failure.
  const AuthorizationFailure({
    required super.code,
    required super.message,
    super.technicalDetail,
    super.statusCode = 403,
    super.debugContext,
    super.cause,
    super.stackTrace,
  });

  /// The permission code the server demanded, when it reported one.
  String? get requiredPermission => debugContext['permission'] as String?;
}

/// The school's subscription or trial has lapsed (402).
///
/// Kept separate from [AuthorizationFailure] because the remedy is
/// commercial, not technical: signing in again will not help, and the UI must
/// say so rather than offering a retry.
final class SubscriptionFailure extends Failure {
  /// Creates a subscription failure.
  const SubscriptionFailure({
    required super.message,
    this.subscriptionStatus,
    this.expiresAt,
    super.technicalDetail,
    super.debugContext,
    super.cause,
    super.stackTrace,
  }) : super(code: ApiErrorCode.subscriptionExpired, statusCode: 402);

  /// `active` | `trial` | `expired` | `inactive`, as `schools.subscription_status`.
  final String? subscriptionStatus;

  /// When access lapsed, if the server reported it.
  final DateTime? expiresAt;
}

/// The request was well-formed but its contents were rejected (400/422).
///
/// [fieldErrors] maps a form field to its messages so a screen can attach
/// errors to inputs instead of showing one opaque banner.
final class ValidationFailure extends Failure {
  /// Creates a validation failure.
  const ValidationFailure({
    required super.message,
    super.code = ApiErrorCode.invalidInput,
    this.fieldErrors = const <String, List<String>>{},
    super.technicalDetail,
    super.statusCode = 400,
    super.debugContext,
    super.cause,
    super.stackTrace,
  });

  /// Field name → messages, derived from the server's `error.details`.
  final Map<String, List<String>> fieldErrors;

  /// The first message recorded against [field], if any.
  String? errorFor(String field) => fieldErrors[field]?.firstOrNull;
}

/// The requested resource does not exist (404).
final class NotFoundFailure extends Failure {
  /// Creates a not-found failure.
  const NotFoundFailure({
    required super.message,
    super.code = ApiErrorCode.notFound,
    super.technicalDetail,
    super.statusCode = 404,
    super.debugContext,
    super.cause,
    super.stackTrace,
  });
}

/// The request conflicts with existing state (409) — a duplicate entry, most
/// often a unique-constraint violation surfaced by `apiErrorHandler.ts`.
final class ConflictFailure extends Failure {
  /// Creates a conflict failure.
  const ConflictFailure({
    required super.message,
    super.code = ApiErrorCode.conflict,
    super.technicalDetail,
    super.statusCode = 409,
    super.debugContext,
    super.cause,
    super.stackTrace,
  });
}

/// The server failed (5xx). The user did nothing wrong and retrying may work.
final class ServerFailure extends Failure {
  /// Creates a server failure.
  const ServerFailure({
    super.code = ApiErrorCode.serverError,
    super.message = 'Something went wrong on our side. Please try again.',
    super.technicalDetail,
    super.statusCode,
    super.debugContext,
    super.cause,
    super.stackTrace,
  });
}

/// The response was not the DRAIS envelope: not JSON, or JSON of an
/// unexpected shape.
///
/// In the field this usually means a captive portal, a school firewall, or a
/// misconfigured reverse proxy — not a backend bug. The message says so,
/// because "Invalid server response" sends users to the wrong place.
final class MalformedResponseFailure extends Failure {
  /// Creates a malformed-response failure.
  const MalformedResponseFailure({
    super.message =
        'Unexpected response from the server. If you are on a public or school '
        'Wi-Fi network, check that you are fully connected.',
    super.technicalDetail,
    super.statusCode,
    super.debugContext,
    super.cause,
    super.stackTrace,
  }) : super(code: ApiErrorCode.malformedResponse);
}

/// The request was cancelled by the app. Never surfaced to the user.
final class CancelledFailure extends Failure {
  /// Creates a cancellation failure.
  const CancelledFailure({
    super.message = 'Request cancelled.',
    super.technicalDetail,
    super.debugContext,
    super.cause,
    super.stackTrace,
  }) : super(code: ApiErrorCode.cancelled);
}

/// Anything that escaped classification. Its existence is a bug report: every
/// occurrence is logged at error level with full context.
final class UnknownFailure extends Failure {
  /// Creates an unknown failure.
  const UnknownFailure({
    super.message = 'Something went wrong. Please try again.',
    super.technicalDetail,
    super.statusCode,
    super.debugContext,
    super.cause,
    super.stackTrace,
  }) : super(code: ApiErrorCode.unknown);
}
