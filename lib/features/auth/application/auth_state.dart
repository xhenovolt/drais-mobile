import 'package:drais/core/error/failure.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';

/// Where the app is in the authentication lifecycle.
///
/// Modelled as an explicit enum rather than a pair of nullable fields, because
/// the router has to make a routing decision on *every* rebuild and
/// `user == null` cannot distinguish "still checking" from "signed out". That
/// ambiguity is the classic cause of a login screen flashing for a moment
/// before the dashboard appears.
enum AuthStatus {
  /// Nothing attempted yet — the state at construction.
  initial,

  /// A stored session is being validated against `/api/auth/me`.
  restoring,

  /// Credentials are in flight.
  authenticating,

  /// A user is signed in. [AuthState.user] is non-null.
  authenticated,

  /// No user is signed in.
  unauthenticated,

  /// A session exists but the app cannot reach the server to validate it.
  ///
  /// **Not** the same as signed out. The user keeps their session; the app
  /// shows an offline notice and retries. Conflating the two would sign out
  /// every teacher who opens the app in a classroom with no signal.
  offlineUnverified,

  /// The session is valid but access is withheld — a lapsed subscription, a
  /// suspended school, or a required password change. Recoverable without
  /// re-authenticating, so the user is *not* dropped back to login.
  blocked,
}

/// Immutable authentication state, consumed by the router and by screens.
class AuthState {
  /// Creates an auth state.
  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.failure,
    this.warning,
  });

  /// The initial state, before bootstrap runs.
  static const AuthState initial = AuthState();

  /// Lifecycle position.
  final AuthStatus status;

  /// The signed-in user, when there is one.
  final AuthUser? user;

  /// The most recent failure, retained so a screen can render it. Cleared on
  /// the next attempt.
  final Failure? failure;

  /// A non-fatal notice from the server — currently only the
  /// `SUBSCRIPTION_EXPIRING` warning that `/api/auth/login` returns. Worth
  /// surfacing because it is the school's only warning before access stops.
  final String? warning;

  /// Whether a request is in flight.
  bool get isBusy =>
      status == AuthStatus.restoring || status == AuthStatus.authenticating;

  /// Whether a user is signed in *and* permitted into the app.
  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;

  /// Whether the session is known-absent, so the login screen should show.
  ///
  /// [AuthStatus.offlineUnverified] deliberately does not count: the user is
  /// not signed out, merely unverifiable right now.
  bool get isSignedOut => status == AuthStatus.unauthenticated;

  /// Whether the user must change their password before continuing.
  bool get requiresPasswordChange => user?.mustChangePassword ?? false;

  /// Whether the school still needs configuring.
  ///
  /// No longer a blocking condition — it drives a banner, not a wall.
  bool get requiresSchoolSetup => user?.needsSetup ?? false;

  /// Whether a lapsed subscription blocks entry.
  bool get isSubscriptionBlocked =>
      user?.subscription?.hasAccess == false || failure is SubscriptionFailure;

  /// Whether [code] is granted. False when signed out — so a permission check
  /// never accidentally passes for an anonymous caller.
  bool can(String code) => user?.can(code) ?? false;

  /// Returns a copy with the given overrides.
  ///
  /// [failure] and [warning] are cleared unless explicitly provided, so a
  /// stale error cannot survive into a successful state. That is the desired
  /// default; `copyWith(failure: x)` sets one deliberately.
  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    Failure? failure,
    String? warning,
    bool keepUser = true,
  }) => AuthState(
    status: status ?? this.status,
    user: user ?? (keepUser ? this.user : null),
    failure: failure,
    warning: warning,
  );

  @override
  String toString() =>
      'AuthState(${status.name}, user: ${user?.id}, '
      'failure: ${failure?.code.wireValue})';
}
