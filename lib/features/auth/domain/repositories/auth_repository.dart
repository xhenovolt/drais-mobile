import 'package:drais/core/error/result.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';

/// The authentication contract the application layer depends on.
///
/// Declared in `domain/` and implemented in `data/` so the dependency points
/// inward: the controller knows this interface and nothing about `dio`,
/// cookies, or JSON. That is what makes the auth flow testable without a
/// server, and what would let the transport change without touching a single
/// screen.
///
/// Every method returns a [Result] — implementations must not throw.
abstract interface class AuthRepository {
  /// Signs in with [email] and [password].
  ///
  /// On success the session cookie is stored and the full identity is loaded
  /// from `/api/auth/me`. Implementations must perform both steps, because
  /// `/api/auth/login` alone returns a thinner user object than the rest of
  /// the app expects.
  Future<Result<AuthUser>> login({
    required String email,
    required String password,
  });

  /// Restores a session from stored cookies at app start.
  ///
  /// Returns `Ok(null)` when there is no session to restore — that is the
  /// normal first-launch path, not an error. Returns `Err` only when a session
  /// existed and something went genuinely wrong.
  Future<Result<AuthUser?>> restoreSession();

  /// Re-reads the current identity from `/api/auth/me`.
  ///
  /// Used after a password change, on resume, and whenever roles or
  /// permissions may have changed server-side. A user's permissions can be
  /// revoked mid-session by an administrator; the app will not notice until it
  /// asks.
  Future<Result<AuthUser>> refreshUser();

  /// Signs out.
  ///
  /// Implementations must clear local session state **even when the server
  /// call fails**. A user who taps "sign out" on a shared school tablet must
  /// end up signed out locally regardless of connectivity.
  Future<Result<void>> logout();

  /// Changes the password of the signed-in user.
  ///
  /// Also the remedy for `mustChangePassword`.
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Registers a **new school** and its first administrator.
  ///
  /// This is how a school that has never used DRAIS gets in. It provisions a
  /// whole tenant in one step, mirroring `POST /api/auth/signup`:
  ///
  /// * a `schools` row on a **trial**, with `setup_complete = false`;
  /// * a **Super Admin** role scoped to that school;
  /// * the caller as a user, holding that role;
  /// * a session, so they are signed in when it returns.
  ///
  /// `setup_complete` stays false deliberately — terms, classes and the
  /// academic calendar are long desk work the web app already does well. The
  /// school exists and the trial is running; the rest is configuration.
  Future<Result<AuthUser>> registerSchool({
    required String schoolName,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? phone,
  });

  /// The email last used to sign in, for pre-filling the login form.
  Future<String?> lastUsedEmail();
}
