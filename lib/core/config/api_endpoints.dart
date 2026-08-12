/// Canonical DRAIS backend endpoint paths.
///
/// **This file is a mirror, not a design.** Every constant here corresponds to
/// a route file in DRAIS LongTerm at `src/app/api/<path>/route.ts`. When a
/// route changes there, change it here — never invent a path the server does
/// not serve, and never let the two drift.
///
/// Paths are origin-relative and include the `/api` prefix.
/// [AppConfig.resolve] prepends the environment's origin.
///
/// ## Auth domains
///
/// DRAIS has three unrelated authentication systems (ADR-0008, ADR-0011). Only
/// one of them is the concern of this app today:
///
/// * **School auth** (`/api/auth/*`, `drais_session` cookie) — implemented.
/// * **Parent portal** (`/api/portal/*`, `/api/parent/*`) — separate identity
///   space with its own OTP flow. Reserved below, deliberately unimplemented.
/// * **Control Center** (`/api/control-center/*`, `drais_control` cookie) —
///   Xhenvolt platform operations. **Out of scope for mobile, permanently.**
///   Shipping operator credentials in a consumer app would collapse the
///   isolation boundary ADR-0008 exists to protect.
library;

/// Endpoint paths grouped by subsystem, mirroring `src/app/api/`.
abstract final class ApiEndpoints {
  // ───────────────────────────────────────────────────────────────────────
  // Platform / diagnostics
  // ───────────────────────────────────────────────────────────────────────

  /// `GET` — liveness + DB connectivity probe. Public (no session required).
  /// Source: `src/app/api/health/route.ts`.
  static const String health = '/api/health';

  /// `GET` — active "What's new" flags. Public.
  /// Source: `src/app/api/feature-flags/route.ts`.
  static const String featureFlags = '/api/feature-flags';

  // ───────────────────────────────────────────────────────────────────────
  // School authentication — src/app/api/auth/
  // ───────────────────────────────────────────────────────────────────────

  /// `POST {email, password}` — issues the `drais_session` cookie.
  static const String login = '/api/auth/login';

  /// `POST {firstName, lastName, email, password, confirmPassword,
  /// schoolName?, schoolId?, phone?}` — registers a school and its first
  /// administrator, or joins an existing school.
  static const String signup = '/api/auth/signup';

  /// `POST` — invalidates the server session and clears cookies.
  static const String logout = '/api/auth/logout';

  /// `GET` — current user, school, subscription, roles and permissions.
  /// This is the session-restoration endpoint.
  static const String me = '/api/auth/me';

  /// `POST` — change password (also satisfies `mustChangePassword`).
  static const String changePassword = '/api/auth/change-password';

  /// `GET` — the user's active sessions across devices.
  static const String sessions = '/api/auth/sessions';

  /// `POST` — revoke every session except the caller's.
  static const String logoutOtherSessions = '/api/auth/sessions/logout-others';

  /// `DELETE` — revoke one specific session.
  static String session(String sessionId) => '/api/auth/sessions/$sessionId';

  /// `GET` — whether the caller is a Control Center impersonation. Public.
  static const String impersonationStatus = '/api/auth/impersonation-status';

  // ───────────────────────────────────────────────────────────────────────
  // Profile — src/app/api/profile/
  // ───────────────────────────────────────────────────────────────────────

  /// `GET` / `PUT` — the authenticated user's own profile.
  static const String profile = '/api/profile';

  // ───────────────────────────────────────────────────────────────────────
  // Reserved for future modules. Declared so that the roadmap is visible
  // from the code, and so nobody re-derives a path by guessing.
  // See docs/ROADMAP.md — none of these are wired up in 1.0.0.
  // ───────────────────────────────────────────────────────────────────────

  /// Attendance — `src/app/api/attendance/`.
  static const String attendance = '/api/attendance';

  /// Finance — `src/app/api/finance/`.
  static const String finance = '/api/finance';

  /// Students — `src/app/api/students/`.
  static const String students = '/api/students';

  /// Notifications — `src/app/api/notifications/`.
  static const String notifications = '/api/notifications';

  /// Dashboard aggregates — `src/app/api/dashboard/`.
  static const String dashboard = '/api/dashboard';

  /// Parent portal login — a **different** identity space (ADR-0009).
  static const String portalLogin = '/api/portal/auth/login';
}
