/// The DRAIS error-code vocabulary, mirrored from the backend.
///
/// ## Two sources, one vocabulary
///
/// LongTerm has a canonical enum in `src/lib/apiResponse.ts` (`ApiErrorCode`),
/// but several hand-written routes — `/api/auth/login` and `/api/auth/me`
/// among them — emit codes that are *not* in it (`INVALID_CREDENTIALS`,
/// `ACCOUNT_PENDING`, `SCHOOL_SUSPENDED`, `SUBSCRIPTION_EXPIRED`, …). Both
/// families are real and reach clients, so both are mirrored here.
///
/// That split is recorded as technical debt in
/// `docs/PARITY.md` → "Divergences observed". This enum is the mobile-side
/// single source of truth until the backend consolidates.
///
/// **Codes are the contract; messages are not.** Branch on [ApiErrorCode],
/// never on the server's English message string — messages are edited freely
/// and are not localised.
library;

/// A machine-readable error identity returned by the DRAIS API.
enum ApiErrorCode {
  // ── Authentication (401) — src/lib/apiResponse.ts ──────────────────────
  /// No valid session was presented.
  unauthorized('UNAUTHORIZED'),

  /// Session token was not recognised.
  sessionInvalid('SESSION_INVALID'),

  /// Session existed but has passed `sessions.expires_at`.
  sessionExpired('SESSION_EXPIRED'),

  /// Session does not grant access to the requested school.
  unauthorizedSchool('UNAUTHORIZED_SCHOOL'),

  /// Emitted by `/api/auth/me` when no session cookie was sent at all.
  notAuthenticated('NOT_AUTHENTICATED'),

  /// Emitted by `/api/auth/login` for a bad email or password. Deliberately
  /// indistinguishable between the two cases, server-side.
  invalidCredentials('INVALID_CREDENTIALS'),

  // ── Authorization (403) ────────────────────────────────────────────────
  /// The session is valid but lacks the required permission.
  forbidden('FORBIDDEN'),

  /// RBAC check against `permissions.code` failed.
  permissionDenied('PERMISSION_DENIED'),

  /// School setup has not been completed; most features are gated.
  setupIncomplete('SETUP_INCOMPLETE'),

  /// The user account exists but has not been approved.
  accountPending('ACCOUNT_PENDING'),

  /// The user account was deactivated, suspended or locked.
  accountInactive('ACCOUNT_INACTIVE'),

  /// The school tenant is suspended.
  schoolSuspended('SCHOOL_SUSPENDED'),

  /// The school tenant is not in `active` status.
  schoolInactive('SCHOOL_INACTIVE'),

  // ── Billing (402) ──────────────────────────────────────────────────────
  /// Subscription or trial has lapsed. Carries subscription detail in the
  /// response body; the user must renew rather than re-authenticate.
  subscriptionExpired('SUBSCRIPTION_EXPIRED'),

  // ── Validation (400) ───────────────────────────────────────────────────
  /// Malformed request.
  badRequest('BAD_REQUEST'),

  /// A field failed validation.
  invalidInput('INVALID_INPUT'),

  /// Email or password absent from a login request.
  missingCredentials('MISSING_CREDENTIALS'),

  /// A required field was null — often a NOT NULL constraint surfaced.
  missingField('MISSING_FIELD'),

  /// Email failed format validation.
  invalidEmail('INVALID_EMAIL'),

  /// Password failed policy validation.
  invalidPassword('INVALID_PASSWORD'),

  // ── Not found (404) ────────────────────────────────────────────────────
  /// Generic not-found.
  notFound('NOT_FOUND'),

  /// The named user does not exist.
  userNotFound('USER_NOT_FOUND'),

  /// The named school does not exist.
  schoolNotFound('SCHOOL_NOT_FOUND'),

  /// The named resource does not exist.
  resourceNotFound('RESOURCE_NOT_FOUND'),

  // ── Conflict (409) ─────────────────────────────────────────────────────
  /// Generic conflict.
  conflict('CONFLICT'),

  /// Email is already registered.
  emailAlreadyExists('EMAIL_ALREADY_EXISTS'),

  /// A unique constraint was violated (`ER_DUP_ENTRY`).
  duplicateEntry('DUPLICATE_ENTRY'),

  // ── Server (5xx) ───────────────────────────────────────────────────────
  /// Unhandled server exception.
  internalError('INTERNAL_ERROR'),

  /// A database operation failed.
  databaseError('DATABASE_ERROR'),

  /// Generic server error — the code most hand-written routes emit.
  serverError('SERVER_ERROR'),

  /// Logout failed server-side. The client clears local state regardless.
  logoutError('LOGOUT_ERROR'),

  // ── Client-side only ───────────────────────────────────────────────────
  /// The device has no usable network connection. Never sent by the server.
  offline('CLIENT_OFFLINE'),

  /// A request exceeded its timeout. Never sent by the server.
  timeout('CLIENT_TIMEOUT'),

  /// The response was not the DRAIS envelope, or was not JSON at all —
  /// typically a proxy error page or a captive portal.
  malformedResponse('CLIENT_MALFORMED_RESPONSE'),

  /// The request was cancelled by the app (screen disposed, user navigated).
  cancelled('CLIENT_CANCELLED'),

  /// Anything not otherwise classified.
  unknown('UNKNOWN');

  const ApiErrorCode(this.wireValue);

  /// The exact string the backend puts in `error.code`.
  final String wireValue;

  /// Resolves a wire value, falling back to [ApiErrorCode.unknown].
  ///
  /// An unrecognised code is expected and safe: the backend may add codes
  /// faster than the app ships. Callers then fall back to HTTP-status
  /// classification, so behaviour degrades rather than breaking.
  static ApiErrorCode fromWire(String? raw) {
    if (raw == null || raw.isEmpty) return ApiErrorCode.unknown;
    final String needle = raw.trim().toUpperCase();
    for (final ApiErrorCode code in ApiErrorCode.values) {
      if (code.wireValue == needle) return code;
    }
    return ApiErrorCode.unknown;
  }

  /// Whether this code means the local session is dead and the user must sign
  /// in again. Drives the global sign-out in `SessionExpiryInterceptor`.
  bool get requiresReauthentication => switch (this) {
    ApiErrorCode.unauthorized ||
    ApiErrorCode.sessionInvalid ||
    ApiErrorCode.sessionExpired ||
    ApiErrorCode.unauthorizedSchool ||
    ApiErrorCode.notAuthenticated => true,
    _ => false,
  };

  /// Whether retrying the identical request could plausibly succeed.
  bool get isRetryable => switch (this) {
    ApiErrorCode.offline ||
    ApiErrorCode.timeout ||
    ApiErrorCode.internalError ||
    ApiErrorCode.serverError ||
    ApiErrorCode.databaseError => true,
    _ => false,
  };
}
