import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/features/auth/application/auth_state.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';
import 'package:drais/features/auth/domain/repositories/auth_repository.dart';

/// Owns authentication state for the whole application.
///
/// Everything that can change who is signed in goes through here: the login
/// form, the splash screen's session restore, the sign-out button, and the
/// network layer's dead-session callback. One owner means one place where the
/// transitions can be wrong, and the router can trust a single source.
///
/// The controller performs **no** authorization of its own. It reports what
/// the server said; the server decides.
class AuthController extends StateNotifier<AuthState> {
  /// Creates the controller.
  AuthController({
    required AuthRepository repository,
    required AppLogger logger,
    void Function()? onSignedIn,
  }) : _repository = repository,
       _logger = logger.child('Auth'),
       _onSignedIn = onSignedIn,
       super(AuthState.initial);

  final AuthRepository _repository;
  final AppLogger _logger;

  /// Called after a successful sign-in so the transport can re-arm its
  /// dead-session guard.
  final void Function()? _onSignedIn;

  /// Restores a stored session. Called once, from the splash screen.
  ///
  /// Never throws and never leaves the state in [AuthStatus.restoring]:
  /// a stuck splash screen with no way forward is the worst outcome here.
  Future<void> restoreSession() async {
    state = state.copyWith(status: AuthStatus.restoring);

    final Result<AuthUser?> result = await _repository.restoreSession();

    switch (result) {
      case Ok<AuthUser?>(:final AuthUser? value):
        if (value == null) {
          _logger.info('No session to restore.');
          state = const AuthState(status: AuthStatus.unauthenticated);
        } else {
          _applySignedIn(value);
        }

      case Err<AuthUser?>(:final Failure failure):
        state = _stateForRestoreFailure(failure);
    }
  }

  /// Signs in with [email] and [password].
  ///
  /// Returns true when the user ended up signed in. The caller uses the
  /// boolean only for local UI decisions — navigation is driven by the router
  /// watching this state, not by the login screen pushing a route.
  Future<bool> login({required String email, required String password}) async {
    if (state.isBusy) return false;

    if (email.trim().isEmpty || password.isEmpty) {
      // Caught locally to save a round trip. The server performs the same
      // check and returns MISSING_CREDENTIALS; this is a courtesy, not a
      // substitute.
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        keepUser: false,
        failure: const ValidationFailure(
          code: ApiErrorCode.missingCredentials,
          message: 'Enter your email and password.',
        ),
      );
      return false;
    }

    state = state.copyWith(status: AuthStatus.authenticating, keepUser: false);

    final Result<AuthUser> result = await _repository.login(
      email: email,
      password: password,
    );

    switch (result) {
      case Ok<AuthUser>(:final AuthUser value):
        _onSignedIn?.call();
        _applySignedIn(value);
        return state.isAuthenticated;

      case Err<AuthUser>(:final Failure failure):
        _logger.info(
          'Sign-in failed.',
          context: <String, Object?>{'code': failure.code.wireValue},
        );
        state = AuthState(
          // A lapsed subscription is not a failed sign-in: the credentials
          // were right, and the screen must say so rather than implying the
          // password was wrong.
          status: failure is SubscriptionFailure
              ? AuthStatus.blocked
              : AuthStatus.unauthenticated,
          failure: failure,
        );
        return false;
    }
  }

  /// Registers a new school and signs the caller in as its first admin.
  ///
  /// Shares the sign-in state machine deliberately: from the app's point of
  /// view this *is* a sign-in that happens to create a tenant first, and
  /// giving it its own status would mean every screen watching auth had a
  /// second case to handle.
  Future<bool> registerSchool({
    required String schoolName,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? phone,
  }) async {
    if (state.isBusy) return false;

    state = state.copyWith(status: AuthStatus.authenticating, keepUser: false);

    final Result<AuthUser> result = await _repository.registerSchool(
      schoolName: schoolName,
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
      phone: phone,
    );

    switch (result) {
      case Ok<AuthUser>(:final AuthUser value):
        _onSignedIn?.call();
        _logger.info(
          'School registered and signed in.',
          context: <String, Object?>{'schoolId': value.schoolId},
        );
        _applySignedIn(value);
        return state.isAuthenticated || state.status == AuthStatus.blocked;

      case Err<AuthUser>(:final Failure failure):
        _logger.info(
          'School registration failed.',
          context: <String, Object?>{'code': failure.code.wireValue},
        );
        state = AuthState(status: AuthStatus.unauthenticated, failure: failure);
        return false;
    }
  }

  /// Re-reads the identity from the server.
  ///
  /// Call on resume and after a password change. An administrator can revoke
  /// a role mid-session and the app will not know until it asks — the server
  /// still enforces it either way, but the UI should stop offering actions
  /// that will now fail.
  Future<void> refresh() async {
    if (!state.isAuthenticated) return;

    final Result<AuthUser> result = await _repository.refreshUser();

    switch (result) {
      case Ok<AuthUser>(:final AuthUser value):
        _applySignedIn(value);

      case Err<AuthUser>(:final Failure failure):
        if (failure.requiresReauthentication) {
          await _forceSignOut(failure.code);
        } else {
          // A transient refresh failure must not disturb a working session.
          _logger.warn(
            'Identity refresh failed; keeping the current session.',
            context: <String, Object?>{'code': failure.code.wireValue},
          );
        }
    }
  }

  /// Signs out and returns to the login screen.
  Future<void> logout() async {
    _logger.info('Sign-out requested.');
    await _repository.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Changes the password, then reloads the identity.
  ///
  /// The reload matters: clearing `users.must_change_password` server-side is
  /// only visible to the app through a fresh `/api/auth/me`, and without it
  /// the user stays trapped on the change-password screen.
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final Result<void> result = await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );

    if (result.isOk) {
      _logger.info('Password changed.');
      await refresh();
    }
    return result;
  }

  /// Invoked by the network layer when the server rejects the session.
  ///
  /// Wired in at composition time via `apiClientProvider`, which is what lets
  /// any request anywhere in the app trigger one orderly sign-out.
  Future<void> handleSessionInvalidated(ApiErrorCode code) =>
      _forceSignOut(code);

  /// The email to pre-fill on the login form.
  Future<String?> lastUsedEmail() => _repository.lastUsedEmail();

  /// Clears a displayed error without changing lifecycle state.
  void clearFailure() {
    if (state.failure == null) return;
    state = state.copyWith(status: state.status);
  }

  // ── Internals ──────────────────────────────────────────────────────────

  /// Applies a loaded identity, choosing between authenticated and blocked.
  ///
  /// The blocking conditions mirror what the backend enforces on every
  /// request. Reproducing them is a UX decision — it lets the app explain the
  /// situation instead of showing a dashboard that 403s on every tile — and
  /// carries no security weight.
  void _applySignedIn(AuthUser user) {
    final bool blocked = !user.canEnterApp;

    state = AuthState(
      status: blocked ? AuthStatus.blocked : AuthStatus.authenticated,
      user: user,
      warning: _warningFor(user),
    );

    _logger.info(
      blocked ? 'Signed in but blocked.' : 'Signed in.',
      context: <String, Object?>{
        'userId': user.id,
        'schoolId': user.schoolId,
        'mustChangePassword': user.mustChangePassword,
        'setupComplete': user.setupComplete,
        'hasAccess': user.subscription?.hasAccess,
      },
    );
  }

  AuthState _stateForRestoreFailure(Failure failure) {
    if (failure is NetworkFailure || failure is TimeoutFailure) {
      // The session is still presumed good — we simply could not check it.
      _logger.info('Session unverified; device appears offline.');
      return AuthState(status: AuthStatus.offlineUnverified, failure: failure);
    }
    if (failure is SubscriptionFailure || failure is AuthorizationFailure) {
      return AuthState(status: AuthStatus.blocked, failure: failure);
    }
    return AuthState(status: AuthStatus.unauthenticated, failure: failure);
  }

  Future<void> _forceSignOut(ApiErrorCode code) async {
    if (state.status == AuthStatus.unauthenticated) return;

    _logger.warn(
      'Forced sign-out.',
      context: <String, Object?>{'code': code.wireValue},
    );

    await _repository.logout();
    state = AuthState(
      status: AuthStatus.unauthenticated,
      failure: AuthenticationFailure(
        code: code,
        message: 'Your session has ended. Please sign in again.',
      ),
    );
  }

  /// Surfaces the server's expiry warning while access still works.
  static String? _warningFor(AuthUser user) {
    final int? days = user.subscription?.daysUntilExpiry;
    if (user.subscription?.expiringSoon != true || days == null) return null;
    return 'This school\'s DRAIS subscription expires in $days day'
        '${days == 1 ? '' : 's'}. Please renew to avoid interruption.';
  }
}
