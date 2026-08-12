import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:drais_server/auth/password.dart';
import 'package:drais_server/auth/rbac.dart';
import 'package:drais_server/auth/session.dart';
import 'package:drais_server/config/env.dart';
import 'package:drais_server/db/database.dart';
import 'package:drais_server/http/api_response.dart';
import 'package:drais_server/http/cookies.dart';

/// `/api/auth/*` — the DRAIS school authentication surface, in Dart.
///
/// ## The contract is not negotiable
///
/// The Flutter client already speaks this contract, and the whole point of
/// this service is that it runs against a Dart backend **without a single line
/// of client change**. Every field name, cookie name, status code and error
/// code below is chosen to match `src/app/api/auth/*/route.ts` exactly.
///
/// Where the platform is inconsistent, this reproduces the inconsistency
/// rather than improving it — a "fix" here is a break for every installed app.
/// The two deliberate corrections are noted in place.
class AuthRoutes {
  /// Creates the auth route group.
  AuthRoutes({required Database db, required ServerEnv env})
      : _db = db,
        _env = env;


  final Database _db;
  final ServerEnv _env;

  /// The mounted router.
  Router get router {
    final Router router = Router()
      ..post('/login', _login)
      ..post('/logout', _logout)
      ..get('/me', _me);
    return router;
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/auth/login
  // ───────────────────────────────────────────────────────────────────────

  Future<Response> _login(Request request) async {
    final Map<String, Object?>? body = await _readJson(request);
    if (body == null) {
      return ApiResponse.badRequest(
        'Invalid request body',
        code: ApiErrorCode.badRequest,
      );
    }

    final String email = (body['email'] as String? ?? '').trim();
    final String password = body['password'] as String? ?? '';

    if (email.isEmpty || password.isEmpty) {
      return ApiResponse.error(
        ApiErrorCode.missingCredentials,
        'Email and password are required',
        status: 400,
      );
    }

    final Row? user = await _db.queryOne(
      '''
      SELECT
        u.id,
        u.school_id,
        u.email,
        u.password_hash,
        u.is_active,
        COALESCE(u.first_name, '') AS first_name,
        COALESCE(u.last_name, '')  AS last_name,
        COALESCE(u.must_change_password, FALSE) AS must_change_password
      FROM users u
      WHERE u.email = ?
        AND u.deleted_at IS NULL
      LIMIT 1
      ''',
      <Object?>[email],
    );

    // Same response whether the account is absent or the password is wrong.
    // The platform is deliberate about this and so is this implementation:
    // distinguishing them turns the login form into an account enumerator.
    if (user == null) {
      return _invalidCredentials();
    }

    // `is_active` is tinyint(1) and the driver returns a Dart bool. Reading
    // it as an int yields null, and defaulting that to 0 rejected EVERY user
    // with "account is pending approval". Coerce through _asBool, which
    // handles bool, 0/1 and '0'/'1' alike.
    if (!_asBool(user['is_active'])) {
      return ApiResponse.error(
        ApiErrorCode.accountPending,
        'Your account is pending approval. Please contact your administrator.',
        status: 403,
      );
    }

    if (!Password.verify(password, user['password_hash'] as String?)) {
      // Best-effort; a counter failure must not turn a wrong password into a 500.
      unawaited(
        _db.execute(
          'UPDATE users SET failed_login_attempts = '
          'COALESCE(failed_login_attempts, 0) + 1 WHERE id = ?',
          <Object?>[user['id']],
        ),
      );
      return _invalidCredentials();
    }

    final int userId = _asInt(user['id'])!;
    final int? schoolId = _asInt(user['school_id']);

    // ── Tenant gates, applied before a session exists ──────────────────
    Row? school;
    if (schoolId != null) {
      school = await _db.queryOne(
        '''
        SELECT id, name, status, setup_complete,
               subscription_status, subscription_end_date, trial_end_date
          FROM schools
         WHERE id = ? AND deleted_at IS NULL
        ''',
        <Object?>[schoolId],
      );

      if (school != null && school['status'] == 'suspended') {
        return ApiResponse.error(
          ApiErrorCode.schoolSuspended,
          'Your school account is suspended. Contact administrator.',
          status: 403,
        );
      }

      if (school != null && _subscriptionLapsed(school)) {
        return ApiResponse.error(
          ApiErrorCode.subscriptionExpired,
          'Your DRAIS subscription has expired. Please renew to regain '
          'access — contact Xhenvolt or your administrator.',
          status: 402,
          extra: <String, Object?>{
            'subscription': <String, Object?>{
              'status': school['subscription_status'],
              'subscriptionEndDate':
                  _isoOrNull(school['subscription_end_date']),
              'trialEndDate': _isoOrNull(school['trial_end_date']),
            },
          },
        );
      }
    }

    // ── Establish the session ──────────────────────────────────────────
    final String token = await Session.create(
      _db,
      userId: userId,
      schoolId: schoolId,
      days: _env.sessionDays,
      ipAddress: clientIp(request),
      userAgent: request.headers['user-agent'],
    );

    unawaited(
      _db.execute(
        'UPDATE users SET last_login_at = NOW(), failed_login_attempts = 0 '
        'WHERE id = ?',
        <Object?>[userId],
      ),
    );

    // ── Identity ───────────────────────────────────────────────────────
    //
    // CORRECTION vs the platform. `/api/auth/login` in LongTerm computes
    // isSuperAdmin by matching role NAMES against 'admin'/'super', so a
    // "Deputy Admin" is handed permissions: ['*'] in that response
    // (docs/PARITY.md §3.2). This uses the same three-way test the session
    // query uses. It is a fix, not a contract change: the field keeps its
    // name and type, and only stops being wrong.
    final List<RoleRecord> roles = schoolId == null
        ? const <RoleRecord>[]
        : await Rbac.rolesFor(_db, userId: userId, schoolId: schoolId);
    final bool isSuperAdmin = roles.any((RoleRecord r) => r.isSuperAdmin);
    final List<String> permissions = schoolId == null
        ? const <String>[]
        : await Rbac.permissionsFor(
            _db,
            userId: userId,
            schoolId: schoolId,
            isSuperAdmin: isSuperAdmin,
          );

    final bool mustChangePassword = _asBool(user['must_change_password']);
    final bool setupComplete =
        school == null ? true : _asBool(school['setup_complete']);

    // The login payload keeps the platform's shape, including roles as bare
    // strings. The client ignores this object and re-reads /api/auth/me
    // anyway — but the shape is part of the contract, so it is preserved.
    final Map<String, Object?> userData = <String, Object?>{
      'id': userId,
      'email': user['email'],
      'firstName': user['first_name'],
      'lastName': user['last_name'],
      'displayName': _displayName(user),
      'schoolId': schoolId,
      'schoolName': school?['name'],
      'setupComplete': setupComplete,
      'roles': roles.map((RoleRecord r) => r.name).toList(growable: false),
      'permissions': permissions,
      'isSuperAdmin': isSuperAdmin,
      'mustChangePassword': mustChangePassword,
    };

    final int maxAge = _env.sessionDays * 24 * 60 * 60;
    final List<String> cookies = <String>[
      Cookies.build(
        Cookies.session,
        token,
        maxAgeSeconds: maxAge,
        secure: _env.secureCookies,
      ),
      if (schoolId != null)
        Cookies.build(
          Cookies.schoolId,
          '$schoolId',
          maxAgeSeconds: maxAge,
          secure: _env.secureCookies,
          httpOnly: false,
        ),
      Cookies.build(
        Cookies.role,
        roles.isNotEmpty
            ? roles.first.name
            : (isSuperAdmin ? 'Admin' : 'Staff'),
        maxAgeSeconds: maxAge,
        secure: _env.secureCookies,
        httpOnly: false,
      ),
      if (mustChangePassword)
        Cookies.build(
          Cookies.forceReset,
          '1',
          maxAgeSeconds: maxAge,
          secure: _env.secureCookies,
          httpOnly: false,
        ),
    ];

    return Cookies.withCookies(
      ApiResponse.ok(<String, Object?>{
        'user': userData,
        'setupComplete': setupComplete,
        'mustChangePassword': mustChangePassword,
      }),
      cookies,
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/auth/me
  // ───────────────────────────────────────────────────────────────────────

  Future<Response> _me(Request request) async {
    final SessionResult result = await Session.resolve(_db, request);

    if (!result.isOk) {
      return _rejectionResponse(result.rejection!);
    }

    final SessionInfo session = result.session!;

    final Row? profile = await _db.queryOne(
      '''
      SELECT u.id, u.email, u.first_name, u.last_name, u.phone, u.avatar_url,
             u.is_active, COALESCE(u.must_change_password, FALSE) AS must_change_password
        FROM users u
       WHERE u.id = ? AND u.deleted_at IS NULL
       LIMIT 1
      ''',
      <Object?>[session.userId],
    );

    if (profile == null) {
      return ApiResponse.unauthorized(
        'Session expired or invalid',
        ApiErrorCode.sessionExpired,
      );
    }

    Row? school;
    bool setupComplete = true;
    if (session.schoolId != 0) {
      school = await _db.queryOne(
        '''
        SELECT id, name, status, setup_complete, email, phone, address,
               school_type, logo_url, currency,
               subscription_status, subscription_type,
               subscription_end_date, trial_end_date
          FROM schools
         WHERE id = ? AND deleted_at IS NULL
        ''',
        <Object?>[session.schoolId],
      );
      if (school != null) setupComplete = _asBool(school['setup_complete']);
    }

    final List<RoleRecord> roles = await Rbac.rolesFor(
      _db,
      userId: session.userId,
      schoolId: session.schoolId,
    );
    final bool isSuperAdmin =
        session.isSuperAdmin || roles.any((RoleRecord r) => r.isSuperAdmin);
    final List<String> permissions = await Rbac.permissionsFor(
      _db,
      userId: session.userId,
      schoolId: session.schoolId,
      isSuperAdmin: isSuperAdmin,
    );

    return ApiResponse.ok(<String, Object?>{
      'user': <String, Object?>{
        'id': session.userId,
        'email': profile['email'],
        'firstName': profile['first_name'] ?? '',
        'lastName': profile['last_name'] ?? '',
        'displayName': _displayName(profile),
        'phone': profile['phone'],
        'avatarUrl': profile['avatar_url'],
        'schoolId': session.schoolId == 0 ? null : session.schoolId,
        'schoolName': school?['name'],
        'school': school == null
            ? null
            : <String, Object?>{
                'id': _asInt(school['id']),
                'name': school['name'],
                'email': school['email'],
                'phone': school['phone'],
                'address': school['address'],
                'schoolType': school['school_type'],
                'logoUrl': school['logo_url'],
                'currency': school['currency'] ?? 'UGX',
                'setupComplete': setupComplete,
              },
        'subscription': school == null ? null : _subscriptionJson(school),
        'setupComplete': setupComplete,
        'roles': roles.map((RoleRecord r) => r.toJson()).toList(growable: false),
        'permissions': permissions,
        'isSuperAdmin': isSuperAdmin,
      },
      'setupComplete': setupComplete,
    });
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/auth/logout
  // ───────────────────────────────────────────────────────────────────────

  Future<Response> _logout(Request request) async {
    final String? token = Cookies.read(request, Cookies.session);

    if (token != null && token.isNotEmpty) {
      try {
        await Session.invalidate(_db, token);
      } on Object {
        // Cookies are cleared regardless. A user who taps sign out is signed
        // out; a database hiccup must not leave a live session on the device.
      }
    }

    return Cookies.withCookies(
      ApiResponse.ok(<String, Object?>{'message': 'Logged out successfully'}),
      <String>[
        Cookies.clear(Cookies.session, secure: _env.secureCookies),
        Cookies.clear(
          Cookies.schoolId,
          secure: _env.secureCookies,
          httpOnly: false,
        ),
        Cookies.clear(
          Cookies.role,
          secure: _env.secureCookies,
          httpOnly: false,
        ),
        Cookies.clear(
          Cookies.forceReset,
          secure: _env.secureCookies,
          httpOnly: false,
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────

  static Response _invalidCredentials() => ApiResponse.error(
        ApiErrorCode.invalidCredentials,
        'Invalid email or password',
        status: 401,
      );

  /// Maps a session refusal to the response the client already understands.
  static Response _rejectionResponse(SessionRejection rejection) =>
      switch (rejection) {
        SessionRejection.missing => ApiResponse.unauthorized(
            'Not authenticated',
            ApiErrorCode.notAuthenticated,
          ),
        SessionRejection.invalid => ApiResponse.unauthorized(
            'Session expired or invalid',
            ApiErrorCode.sessionExpired,
          ),
        // A deleted school leaves the session unusable and unrecoverable, so
        // it is reported as a dead session — the client signs out and the user
        // sees the login screen, which is the only sensible destination.
        SessionRejection.schoolDeleted => ApiResponse.unauthorized(
            'Session expired or invalid',
            ApiErrorCode.sessionExpired,
          ),
        SessionRejection.schoolSuspended => ApiResponse.forbidden(
            'This school account is not active',
            code: ApiErrorCode.schoolInactive,
          ),
        // 402, not 403: the credentials are fine and signing in again will not
        // help. The client shows the renewal screen rather than the login form.
        SessionRejection.subscriptionExpired => ApiResponse.error(
            ApiErrorCode.subscriptionExpired,
            'Your subscription has expired. Please subscribe to continue '
            'using DRAIS.',
            status: 402,
          ),
      };

  Map<String, Object?> _subscriptionJson(Row school) {
    final DateTime now = DateTime.now();
    final DateTime? subEnd = _asDate(school['subscription_end_date']);
    final DateTime? trialEnd = _asDate(school['trial_end_date']);
    final DateTime? effective = subEnd ?? trialEnd;
    final int? daysUntilExpiry = effective?.difference(now).inDays;

    return <String, Object?>{
      'status': school['subscription_status'] ?? 'unknown',
      'type': school['subscription_type'],
      'trialEndDate': _isoOrNull(school['trial_end_date']),
      'trialDaysRemaining': trialEnd?.difference(now).inDays,
      'subscriptionEndDate': _isoOrNull(school['subscription_end_date']),
      'subscriptionDaysRemaining': subEnd?.difference(now).inDays,
      'hasAccess': !_subscriptionLapsed(school),
      'daysUntilExpiry': daysUntilExpiry,
      'expiringSoon': daysUntilExpiry != null &&
          daysUntilExpiry >= 0 &&
          daysUntilExpiry <= 14,
    };
  }

  static bool _subscriptionLapsed(Row school) {
    final String? status = school['subscription_status'] as String?;
    if (status == 'expired' || status == 'inactive') return true;

    final DateTime now = DateTime.now();
    final DateTime? subEnd = _asDate(school['subscription_end_date']);
    final DateTime? trialEnd = _asDate(school['trial_end_date']);

    if (status == 'active' && subEnd != null && subEnd.isBefore(now)) return true;
    if (status == 'trial' && trialEnd != null && trialEnd.isBefore(now)) {
      return true;
    }
    return false;
  }

  static String _displayName(Row row) {
    final String composed =
        '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}'.trim();
    return composed.isEmpty ? (row['email'] as String? ?? '') : composed;
  }

  static Future<Map<String, Object?>?> _readJson(Request request) async {
    try {
      final String body = await request.readAsString();
      if (body.isEmpty) return null;
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return decoded
          .map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v));
    } on Object {
      return null;
    }
  }

  static String? _isoOrNull(Object? value) {
    final DateTime? date = _asDate(value);
    return date?.toIso8601String();
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String v = value.trim().toLowerCase();
      return v == '1' || v == 'true';
    }
    return false;
  }

  static DateTime? _asDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
