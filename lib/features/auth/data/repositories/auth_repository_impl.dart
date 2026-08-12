import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/network/api_response.dart';
import 'package:drais/core/storage/cache_store.dart';
import 'package:drais/core/storage/cookie_store.dart';
import 'package:drais/core/storage/preferences_store.dart';
import 'package:drais/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:drais/features/auth/data/dtos/login_request_dto.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';
import 'package:drais/features/auth/domain/repositories/auth_repository.dart';

/// The default [AuthRepository], backed by the DRAIS HTTP API.
///
/// Owns the *orchestration* the endpoints do not provide on their own:
/// login is two calls, sign-out must clean up locally whatever the server
/// says, and session restoration has to distinguish "no session" from
/// "session rejected".
class AuthRepositoryImpl implements AuthRepository {
  /// Creates the repository.
  AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required CookieStore cookieStore,
    required PreferencesStore preferences,
    required CacheStore cacheStore,
    required AppLogger logger,
  }) : _remote = remote,
       _cookies = cookieStore,
       _prefs = preferences,
       _cache = cacheStore,
       _logger = logger.child('AuthRepository');

  final AuthRemoteDataSource _remote;
  final CookieStore _cookies;
  final PreferencesStore _prefs;
  final CacheStore _cache;
  final AppLogger _logger;

  @override
  Future<Result<AuthUser>> login({
    required String email,
    required String password,
  }) async {
    // Any residue from a previous user must go before a new session begins.
    // Signing in as a different user on a shared school tablet while a stale
    // cache survives would show one user another's data — the server did
    // nothing wrong, and the leak would still be real.
    await _clearLocalState(clearCookies: true);

    final Result<ApiEnvelope<AuthUser>> loginResult = await _remote.login(
      LoginRequestDto(email: email, password: password),
    );

    if (loginResult case Err<ApiEnvelope<AuthUser>>(:final Failure failure)) {
      _logger.info(
        'Sign-in rejected.',
        context: <String, Object?>{'code': failure.code.wireValue},
      );
      return Err<AuthUser>(failure);
    }

    if (!_cookies.hasSession) {
      // The API said success but set no session cookie. Almost always a
      // reverse proxy stripping Set-Cookie, or an http/https mismatch — worth
      // saying plainly, because "login failed" would send the user in circles.
      _logger.error(
        'Login succeeded but no session cookie was received.',
        context: <String, Object?>{'email': email},
      );
      return Err<AuthUser>(
        const AuthenticationFailure(
          code: ApiErrorCode.sessionInvalid,
          message:
              'Signed in, but the session could not be stored. '
              'Check that you are connecting to the correct DRAIS server.',
          technicalDetail:
              'No drais_session cookie in the login response headers.',
        ),
      );
    }

    await _prefs.setRememberedEmail(email);

    // Load the full identity. The login payload alone is too thin: its roles
    // are bare strings, it has no school detail, and — critically — its
    // `isSuperAdmin` is computed by matching role names against 'admin',
    // which is looser than the server's own session check. Using it would let
    // the app draw a super-admin UI for a "Deputy Admin" who is not one.
    return _loadIdentity(
      onFailure: (Failure failure) => _logger.warn(
        'Session established but identity load failed.',
        context: <String, Object?>{'code': failure.code.wireValue},
      ),
    );
  }

  @override
  Future<Result<AuthUser?>> restoreSession() async {
    await _cookies.load();

    if (!_cookies.hasSession) {
      // Not an error: first launch, or a session that expired while away.
      _logger.debug('No stored session to restore.');
      return const Ok<AuthUser?>(null);
    }

    final Result<AuthUser> result = await _loadIdentity();

    return switch (result) {
      Ok<AuthUser>(:final AuthUser value) => Ok<AuthUser?>(value),
      Err<AuthUser>(:final Failure failure) => await _interpretRestoreFailure(
        failure,
      ),
    };
  }

  /// Decides whether a failed restore means "signed out" or "try again later".
  ///
  /// The distinction matters at boot. A rejected session must clear local
  /// state and show the login screen. A *network* failure must not — a teacher
  /// opening the app in a classroom with no signal should not be signed out
  /// and forced to re-authenticate once they find a connection.
  Future<Result<AuthUser?>> _interpretRestoreFailure(Failure failure) async {
    if (failure.requiresReauthentication) {
      _logger.info(
        'Stored session was rejected; clearing local state.',
        context: <String, Object?>{'code': failure.code.wireValue},
      );
      await _clearLocalState(clearCookies: true);
      return const Ok<AuthUser?>(null);
    }

    if (failure is NetworkFailure || failure is TimeoutFailure) {
      _logger.info('Session restore deferred — device is offline.');
      return Err<AuthUser?>(failure);
    }

    // A 402 (subscription) or 403 (suspended school) means the session is
    // valid but access is withheld. Keep the cookies: the situation is
    // recoverable without re-authentication once the school renews.
    _logger.warn(
      'Session restore blocked.',
      context: <String, Object?>{'code': failure.code.wireValue},
    );
    return Err<AuthUser?>(failure);
  }

  @override
  Future<Result<AuthUser>> refreshUser() => _loadIdentity();

  @override
  Future<Result<void>> logout() async {
    final Result<ApiEnvelope<void>> result = await _remote.logout();

    // Local state is cleared unconditionally. A user who taps "sign out"
    // is signed out — a failed network call must never leave a live session
    // cookie on the device. The server-side session may outlive it; that is
    // the lesser evil, and the session expires on its own within seven days.
    await _clearLocalState(clearCookies: true);

    if (result case Err<ApiEnvelope<void>>(:final Failure failure)) {
      _logger.warn(
        'Server sign-out failed; local session cleared anyway.',
        context: <String, Object?>{'code': failure.code.wireValue},
      );
      // Reported as success: from the user's point of view they are signed
      // out, and showing an error would invite them to tap it again.
      return const Ok<void>(null);
    }

    _logger.info('Signed out.');
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final Result<ApiEnvelope<void>> result = await _remote.changePassword(
      ChangePasswordRequestDto(
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
    );

    return switch (result) {
      Ok<ApiEnvelope<void>>() => const Ok<void>(null),
      Err<ApiEnvelope<void>>(:final Failure failure) => Err<void>(failure),
    };
  }

  @override
  Future<Result<AuthUser>> registerSchool({
    required String schoolName,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    String? phone,
  }) async {
    await _clearLocalState(clearCookies: true);

    final Result<ApiEnvelope<void>> result = await _remote.signup(
      <String, Object?>{
        'schoolName': schoolName.trim(),
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
        // The route validates the pair server-side; sending both keeps the
        // client honest about what the contract expects rather than relying
        // on it being ignored.
        'confirmPassword': password,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
    );

    if (result case Err<ApiEnvelope<void>>(:final Failure failure)) {
      _logger.info(
        'School registration rejected.',
        context: <String, Object?>{'code': failure.code.wireValue},
      );
      return Err<AuthUser>(failure);
    }

    if (!_cookies.hasSession) {
      return Err<AuthUser>(
        const AuthenticationFailure(
          code: ApiErrorCode.sessionInvalid,
          message:
              'Your school was created, but the session could not be '
              'stored. Try signing in.',
          technicalDetail: 'No drais_session cookie in the signup response.',
        ),
      );
    }

    await _prefs.setRememberedEmail(email);

    // Same reasoning as login: the signup payload is thinner than /me, so the
    // identity is loaded from one place only.
    return _loadIdentity();
  }

  @override
  Future<String?> lastUsedEmail() async => _prefs.rememberedEmail;

  /// Loads the full identity from `/api/auth/me`.
  Future<Result<AuthUser>> _loadIdentity({
    void Function(Failure failure)? onFailure,
  }) async {
    final Result<ApiEnvelope<AuthUser>> result = await _remote.me();

    switch (result) {
      case Ok<ApiEnvelope<AuthUser>>(:final ApiEnvelope<AuthUser> value):
        final AuthUser? user = value.data;
        if (user == null) {
          // 200 with `success: true` and no `user` — a contract break, not a
          // sign-out condition.
          _logger.error('/api/auth/me returned no user object.');
          return Err<AuthUser>(
            const MalformedResponseFailure(
              technicalDetail: 'Missing "user" key in /api/auth/me response.',
            ),
          );
        }
        await _prefs.setLastSessionCheckAt(DateTime.now());
        _logger.info(
          'Identity loaded.',
          context: <String, Object?>{
            'userId': user.id,
            'schoolId': user.schoolId,
            'roles': user.roles.length,
            'superAdmin': user.isSuperAdmin,
          },
        );
        return Ok<AuthUser>(user);

      case Err<ApiEnvelope<AuthUser>>(:final Failure failure):
        onFailure?.call(failure);
        return Err<AuthUser>(failure);
    }
  }

  /// Clears device-side session state.
  ///
  /// The cache goes with it, always: cached responses are tenant data, and a
  /// user's class lists must not survive into the next session on a shared
  /// device. Theme and locale are preserved — they describe the device, not
  /// the person.
  Future<void> _clearLocalState({required bool clearCookies}) async {
    if (clearCookies) await _cookies.clear();
    await _cache.clearAll();
    await _prefs.clearUserScoped();
  }
}
