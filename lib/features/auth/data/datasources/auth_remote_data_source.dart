import 'package:drais/core/config/api_endpoints.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/network/api_client.dart';
import 'package:drais/core/network/api_response.dart';
import 'package:drais/features/auth/data/dtos/auth_user_dto.dart';
import 'package:drais/features/auth/data/dtos/login_request_dto.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';

/// Thin, typed binding to the DRAIS authentication endpoints.
///
/// One method per route, no orchestration and no caching — those belong to the
/// repository. Keeping this layer mechanical means a change to a backend route
/// has exactly one place to land, and the diff against
/// `src/app/api/auth/*/route.ts` stays readable.
class AuthRemoteDataSource {
  /// Creates the data source.
  const AuthRemoteDataSource(this._api);

  final ApiClient _api;

  /// `POST /api/auth/login`.
  ///
  /// Establishes the server session and sets the `drais_session` cookie, which
  /// the cookie interceptor captures automatically. The returned user is the
  /// *thin* shape — the repository follows up with [me] for the full identity.
  ///
  /// The response may also carry a top-level `warning` object
  /// (`SUBSCRIPTION_EXPIRING`), preserved in the envelope's raw body for the
  /// caller to surface as a renewal banner.
  Future<Result<ApiEnvelope<AuthUser>>> login(LoginRequestDto request) =>
      _api.post<AuthUser>(
        ApiEndpoints.login,
        body: request.toJson(),
        dataKey: 'user',
        fromJson: (Object json) =>
            AuthUserDto.fromJson(json as Map<String, Object?>),
      );

  /// `GET /api/auth/me`.
  ///
  /// The canonical identity endpoint: user, school, subscription, roles and
  /// permissions. Also the session-validity probe — a 401 here means the
  /// session is gone.
  ///
  /// The payload sits at the top-level `user` key, and `setupComplete` sits
  /// beside it rather than inside it, so both are read explicitly.
  Future<Result<ApiEnvelope<AuthUser>>> me() => _api.get<AuthUser>(
    ApiEndpoints.me,
    dataKey: 'user',
    fromJson: (Object json) =>
        AuthUserDto.fromJson(json as Map<String, Object?>),
  );

  /// `POST /api/auth/logout`.
  ///
  /// Marks the session inactive server-side and returns cookie-clearing
  /// headers, which the cookie interceptor applies.
  Future<Result<ApiEnvelope<void>>> logout() =>
      _api.post<void>(ApiEndpoints.logout);

  /// `POST /api/auth/change-password`.
  Future<Result<ApiEnvelope<void>>> changePassword(
    ChangePasswordRequestDto request,
  ) => _api.post<void>(ApiEndpoints.changePassword, body: request.toJson());

  /// `POST /api/auth/signup`.
  ///
  /// Creates a school and its first administrator when `schoolName` is given,
  /// or joins an existing school when `schoolId` is. Sets the same session
  /// cookie login does, so the caller is signed in on success.
  Future<Result<ApiEnvelope<void>>> signup(Map<String, Object?> body) =>
      _api.post<void>(ApiEndpoints.signup, body: body);

  /// `GET /api/health` — server liveness and DB connectivity.
  ///
  /// Public, so it works before sign-in. This is the only honest test of
  /// reachability, as opposed to the radio state `connectivity_plus` reports.
  Future<Result<ApiEnvelope<void>>> health() =>
      _api.get<void>(ApiEndpoints.health, cacheFor: null);
}
