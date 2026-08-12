import 'dart:math';

import 'package:drais/core/constants/storage_keys.dart';
import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/storage/cache_store.dart';
import 'package:drais/core/storage/preferences_store.dart';
import 'package:drais/core/storage/secure_store.dart';
import 'package:drais/features/auth/data/direct/direct_password.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';
import 'package:drais/features/auth/domain/entities/permission_set.dart';
import 'package:drais/features/auth/domain/entities/role.dart';
import 'package:drais/features/auth/domain/entities/school_summary.dart';
import 'package:drais/features/auth/domain/entities/subscription_status.dart';
import 'package:drais/features/auth/domain/repositories/auth_repository.dart';

/// Authentication against TiDB Cloud, with no server in between.
///
/// Implements the same [AuthRepository] the HTTP repository does, so nothing
/// above `data/` knows which is in use. That is what makes the two modes
/// interchangeable at runtime rather than a fork of the application.
///
/// ## Sessions without cookies
///
/// There is no HTTP layer, so there is no `Set-Cookie`. The session token —
/// still 32 random bytes, hex-encoded, still a row in `sessions` — is stored in
/// the platform keystore instead. A session created here is a **real DRAIS
/// session**: it appears in the user's device list on the web app and can be
/// revoked from there, because it is the same table.
///
/// ## What this mode gives up, stated plainly
///
/// With no server, tenant scope and authorization are enforced by this code,
/// on the device. Every query below derives `school_id` from the validated
/// session row and never from anything the UI holds — the same discipline the
/// server applies, for the same reason. But it is discipline, not a boundary:
/// anyone who can modify the app or read its configuration can reach the whole
/// database.
///
/// That is acceptable on a machine the school controls. It is not acceptable
/// on a handset that leaves the building. See `docs/DEPLOYMENT_MODES.md`.
class AuthDirectRepository implements AuthRepository {
  /// Creates a direct-mode auth repository.
  AuthDirectRepository({
    required DraisDatabase database,
    required SecureStore secureStore,
    required PreferencesStore preferences,
    required CacheStore cacheStore,
    required AppLogger logger,
    this.sessionDays = 7,
  }) : _db = database,
       _secure = secureStore,
       _prefs = preferences,
       _cache = cacheStore,
       _logger = logger.child('AuthDirect');

  final DraisDatabase _db;
  final SecureStore _secure;
  final PreferencesStore _prefs;
  final CacheStore _cache;
  final AppLogger _logger;

  /// Session lifetime. Seven days, matching the platform — and like the
  /// platform, it does not slide.
  final int sessionDays;

  static final Random _random = Random.secure();

  @override
  Future<Result<AuthUser>> login({
    required String email,
    required String password,
  }) async {
    // Clear any previous user's residue before a new session begins. On a
    // shared school machine, a stale cache surviving a user switch would show
    // one person another's data.
    await _clearLocalState();

    try {
      final Row? user = await _db.queryOne(
        '''
        SELECT u.id, u.school_id, u.email, u.password_hash, u.is_active,
               COALESCE(u.first_name, '') AS first_name,
               COALESCE(u.last_name, '')  AS last_name,
               COALESCE(u.must_change_password, FALSE) AS must_change_password
          FROM users u
         WHERE u.email = ? AND u.deleted_at IS NULL
         LIMIT 1
        ''',
        <Object?>[email.trim().toLowerCase()],
      );

      // Identical response whether the account is absent or the password is
      // wrong — otherwise the login form becomes an account enumerator.
      if (user == null ||
          !DirectPassword.verify(
            password,
            SqlValue.asString(user['password_hash']),
          )) {
        if (user != null) {
          await _db
              .execute(
                'UPDATE users SET failed_login_attempts = '
                'COALESCE(failed_login_attempts, 0) + 1 WHERE id = ?',
                <Object?>[user['id']],
              )
              .catchError((Object _) => 0);
        }
        return const Err<AuthUser>(
          AuthenticationFailure(
            code: ApiErrorCode.invalidCredentials,
            message: 'Invalid email or password.',
          ),
        );
      }

      // `is_active` is tinyint(1) and the driver hands it back as a Dart
      // bool, not an int. Reading it as an int yields null, so an int
      // comparison silently lets a DEACTIVATED account sign in. Coerce.
      if (!SqlValue.asBool(user['is_active'])) {
        return const Err<AuthUser>(
          AuthorizationFailure(
            code: ApiErrorCode.accountPending,
            message:
                'Your account is pending approval. '
                'Please contact your administrator.',
          ),
        );
      }

      final int userId = SqlValue.asInt(user['id'])!;
      final int? schoolId = SqlValue.asInt(user['school_id']);

      final Row? school = schoolId == null ? null : await _loadSchool(schoolId);

      final Failure? blocked = _tenantBlock(school);
      if (blocked != null) return Err<AuthUser>(blocked);

      final String token = await _createSession(userId, schoolId);
      await _secure.write(SecureStorageKeys.directSessionToken, token);
      await _prefs.setRememberedEmail(email);

      await _db
          .execute(
            'UPDATE users SET last_login_at = NOW(), '
            'failed_login_attempts = 0 WHERE id = ?',
            <Object?>[userId],
          )
          .catchError((Object _) => 0);

      _logger.info(
        'Signed in (direct).',
        context: <String, Object?>{'userId': userId, 'schoolId': schoolId},
      );

      return Ok<AuthUser>(
        await _buildUser(userId: userId, schoolId: schoolId, school: school),
      );
    } on Failure catch (failure) {
      return Err<AuthUser>(failure);
    }
  }

  @override
  Future<Result<AuthUser?>> restoreSession() async {
    final String? token = await _secure.read(
      SecureStorageKeys.directSessionToken,
    );
    if (token == null || token.isEmpty) {
      _logger.debug('No stored session to restore.');
      return const Ok<AuthUser?>(null);
    }

    final Result<AuthUser> result = await _loadFromSession(token);

    return switch (result) {
      Ok<AuthUser>(:final AuthUser value) => Ok<AuthUser?>(value),
      Err<AuthUser>(:final Failure failure) => await _interpretRestore(failure),
    };
  }

  /// Distinguishes "your session is dead" from "the database is unreachable".
  ///
  /// The second must not sign anyone out: a teacher opening the app with no
  /// connectivity keeps their session and retries later.
  Future<Result<AuthUser?>> _interpretRestore(Failure failure) async {
    if (failure.requiresReauthentication) {
      await _clearLocalState();
      return const Ok<AuthUser?>(null);
    }
    return Err<AuthUser?>(failure);
  }

  @override
  Future<Result<AuthUser>> refreshUser() async {
    final String? token = await _secure.read(
      SecureStorageKeys.directSessionToken,
    );
    if (token == null || token.isEmpty) {
      return const Err<AuthUser>(
        AuthenticationFailure(
          code: ApiErrorCode.notAuthenticated,
          message: 'Your session has ended. Please sign in again.',
        ),
      );
    }
    return _loadFromSession(token);
  }

  @override
  Future<Result<void>> logout() async {
    final String? token = await _secure.read(
      SecureStorageKeys.directSessionToken,
    );

    if (token != null && token.isNotEmpty) {
      try {
        await _db.execute(
          'UPDATE sessions SET is_active = FALSE, updated_at = NOW() '
          'WHERE session_token = ?',
          <Object?>[token],
        );
      } on Object {
        // Local state is cleared regardless. A user who taps sign out is
        // signed out; the row expires on its own within seven days.
      }
    }

    await _clearLocalState();
    _logger.info('Signed out (direct).');
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final String? token = await _secure.read(
      SecureStorageKeys.directSessionToken,
    );
    if (token == null) {
      return const Err<void>(
        AuthenticationFailure(
          code: ApiErrorCode.notAuthenticated,
          message: 'Your session has ended. Please sign in again.',
        ),
      );
    }

    try {
      final Row? row = await _db.queryOne(
        '''
        SELECT u.id, u.password_hash
          FROM sessions s
          JOIN users u ON u.id = s.user_id
         WHERE s.session_token = ? AND s.is_active = TRUE
           AND s.expires_at > NOW() AND u.deleted_at IS NULL
         LIMIT 1
        ''',
        <Object?>[token],
      );

      if (row == null) {
        return const Err<void>(
          AuthenticationFailure(
            code: ApiErrorCode.sessionExpired,
            message: 'Your session has ended. Please sign in again.',
          ),
        );
      }

      if (!DirectPassword.verify(
        currentPassword,
        SqlValue.asString(row['password_hash']),
      )) {
        return const Err<void>(
          ValidationFailure(
            code: ApiErrorCode.invalidPassword,
            message: 'Your current password is not correct.',
          ),
        );
      }

      await _db.execute(
        'UPDATE users SET password_hash = ?, must_change_password = FALSE, '
        'updated_at = NOW() WHERE id = ?',
        <Object?>[DirectPassword.hash(newPassword), row['id']],
      );

      _logger.info('Password changed (direct).');
      return const Ok<void>(null);
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
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
    final String normalisedEmail = email.trim().toLowerCase();

    try {
      // An email already in use is the one failure a user can act on, so it is
      // checked first and reported plainly rather than surfacing as a
      // duplicate-key error from three inserts later.
      final Row? existing = await _db.queryOne(
        'SELECT id FROM users WHERE email = ? AND deleted_at IS NULL LIMIT 1',
        <Object?>[normalisedEmail],
      );
      if (existing != null) {
        return const Err<AuthUser>(
          ConflictFailure(
            code: ApiErrorCode.emailAlreadyExists,
            message:
                'An account with that email already exists. '
                'Sign in instead, or use a different email.',
          ),
        );
      }

      await _clearLocalState();

      // ── The tenant ────────────────────────────────────────────────────
      //
      // setup_complete stays false: the school exists and the trial runs, but
      // terms, classes and the calendar are configured on the web. Marking it
      // complete here would let someone into an app with no academic year.
      final DateTime trialEnds = DateTime.now().add(const Duration(days: 30));

      await _db.execute(
        '''
        INSERT INTO schools
          (name, status, setup_complete, subscription_status,
           subscription_type, trial_end_date, created_at, updated_at)
        VALUES (?, 'active', FALSE, 'trial', 'trial', ?, NOW(), NOW())
        ''',
        <Object?>[schoolName.trim(), trialEnds],
      );

      final Row? schoolRow = await _db.queryOne(
        'SELECT id FROM schools WHERE name = ? AND deleted_at IS NULL '
        'ORDER BY id DESC LIMIT 1',
        <Object?>[schoolName.trim()],
      );
      final int? schoolId = SqlValue.asInt(schoolRow?['id']);
      if (schoolId == null) {
        return const Err<AuthUser>(
          ServerFailure(
            message: 'The school could not be created. Please try again.',
            technicalDetail: 'schools INSERT produced no readable row',
          ),
        );
      }

      // ── The role ──────────────────────────────────────────────────────
      //
      // slug='super_admin' matters more than the name: the platform's
      // super-admin test accepts the flag, the slug, or the canonical name,
      // and the slug is the one nobody renames by accident.
      await _db.execute(
        '''
        INSERT INTO roles
          (school_id, name, slug, description, is_super_admin, is_active,
           created_at, updated_at)
        VALUES (?, 'Super Admin', 'super_admin',
                'Full access to this school', TRUE, TRUE, NOW(), NOW())
        ''',
        <Object?>[schoolId],
      );

      final Row? roleRow = await _db.queryOne(
        "SELECT id FROM roles WHERE school_id = ? AND slug = 'super_admin' "
        'ORDER BY id DESC LIMIT 1',
        <Object?>[schoolId],
      );
      final int? roleId = SqlValue.asInt(roleRow?['id']);

      // ── The person ────────────────────────────────────────────────────
      await _db.execute(
        '''
        INSERT INTO users
          (school_id, first_name, last_name, email, phone, password_hash,
           is_active, must_change_password, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, TRUE, FALSE, NOW(), NOW())
        ''',
        <Object?>[
          schoolId,
          firstName.trim(),
          lastName.trim(),
          normalisedEmail,
          phone?.trim(),
          DirectPassword.hash(password),
        ],
      );

      final Row? userRow = await _db.queryOne(
        'SELECT id FROM users WHERE email = ? AND deleted_at IS NULL LIMIT 1',
        <Object?>[normalisedEmail],
      );
      final int? userId = SqlValue.asInt(userRow?['id']);
      if (userId == null) {
        return const Err<AuthUser>(
          ServerFailure(
            message: 'Your account could not be created. Please try again.',
            technicalDetail: 'users INSERT produced no readable row',
          ),
        );
      }

      if (roleId != null) {
        await _db.execute(
          '''
          INSERT INTO user_roles
            (user_id, role_id, school_id, is_active, assigned_at)
          VALUES (?, ?, ?, TRUE, NOW())
          ''',
          <Object?>[userId, roleId, schoolId],
        );
      }

      // ── Sign them in ──────────────────────────────────────────────────
      final String token = await _createSession(userId, schoolId);
      await _secure.write(SecureStorageKeys.directSessionToken, token);
      await _prefs.setRememberedEmail(normalisedEmail);

      _logger.info(
        'School registered.',
        context: <String, Object?>{'schoolId': schoolId, 'userId': userId},
      );

      final Row? school = await _loadSchool(schoolId);
      return Ok<AuthUser>(
        await _buildUser(userId: userId, schoolId: schoolId, school: school),
      );
    } on Failure catch (failure) {
      return Err<AuthUser>(failure);
    }
  }

  @override
  Future<String?> lastUsedEmail() async => _prefs.rememberedEmail;

  // ── Internals ──────────────────────────────────────────────────────────

  /// Validates a session token and builds the identity behind it.
  ///
  /// Applies the gates the server applies on *every* request — soft-deleted
  /// school, suspended school, lapsed subscription — not just at login. A
  /// school suspended mid-session loses access at its next refresh.
  Future<Result<AuthUser>> _loadFromSession(String token) async {
    try {
      final Row? row = await _db.queryOne(
        '''
        SELECT s.user_id, s.school_id
          FROM sessions s
          JOIN users u ON u.id = s.user_id
         WHERE s.session_token = ?
           AND s.is_active = TRUE
           AND s.expires_at > NOW()
           AND u.deleted_at IS NULL
         LIMIT 1
        ''',
        <Object?>[token],
      );

      if (row == null) {
        return const Err<AuthUser>(
          AuthenticationFailure(
            code: ApiErrorCode.sessionExpired,
            message: 'Your session has ended. Please sign in again.',
          ),
        );
      }

      final int userId = SqlValue.asInt(row['user_id'])!;
      final int? schoolId = SqlValue.asInt(row['school_id']);
      final Row? school = schoolId == null ? null : await _loadSchool(schoolId);

      final Failure? blocked = _tenantBlock(school);
      if (blocked != null) return Err<AuthUser>(blocked);

      // Touch activity without extending expiry — the platform has no sliding
      // renewal, and neither does this.
      await _db
          .execute(
            'UPDATE sessions SET last_activity_at = NOW() '
            'WHERE session_token = ? AND is_active = TRUE',
            <Object?>[token],
          )
          .catchError((Object _) => 0);

      await _prefs.setLastSessionCheckAt(DateTime.now());

      return Ok<AuthUser>(
        await _buildUser(userId: userId, schoolId: schoolId, school: school),
      );
    } on Failure catch (failure) {
      return Err<AuthUser>(failure);
    }
  }

  Future<Row?> _loadSchool(int schoolId) => _db.queryOne(
    '''
        SELECT id, name, status, setup_complete, email, phone, address,
               school_type, logo_url, currency,
               subscription_status, subscription_type,
               subscription_end_date, trial_end_date
          FROM schools
         WHERE id = ? AND deleted_at IS NULL
        ''',
    <Object?>[schoolId],
  );

  /// The tenant gates, in the order the platform applies them.
  Failure? _tenantBlock(Row? school) {
    if (school == null) return null;

    final String? status = SqlValue.asString(school['status']);
    if (status == 'suspended' || status == 'archived') {
      return const AuthorizationFailure(
        code: ApiErrorCode.schoolSuspended,
        message: 'Your school account is suspended. Contact administrator.',
      );
    }

    if (_subscriptionLapsed(school)) {
      return SubscriptionFailure(
        message:
            'This school\'s DRAIS subscription has expired. '
            'Please renew to restore access.',
        subscriptionStatus: SqlValue.asString(school['subscription_status']),
        expiresAt:
            SqlValue.asDate(school['subscription_end_date']) ??
            SqlValue.asDate(school['trial_end_date']),
      );
    }
    return null;
  }

  /// Assembles the full identity: roles, permissions, school, subscription.
  Future<AuthUser> _buildUser({
    required int userId,
    required int? schoolId,
    required Row? school,
  }) async {
    final Row? profile = await _db.queryOne(
      '''
      SELECT u.id, u.email, u.first_name, u.last_name, u.phone, u.avatar_url,
             COALESCE(u.must_change_password, FALSE) AS must_change_password
        FROM users u WHERE u.id = ? LIMIT 1
      ''',
      <Object?>[userId],
    );

    final List<Role> roles = schoolId == null
        ? const <Role>[]
        : await _loadRoles(userId, schoolId);
    final bool isSuperAdmin = roles.any((Role r) => r.isSuperAdmin);
    final PermissionSet permissions = schoolId == null
        ? PermissionSet.empty
        : await _loadPermissions(userId, schoolId, isSuperAdmin);

    final bool setupComplete = school == null
        ? true
        : SqlValue.asBool(school['setup_complete']);

    final String firstName = SqlValue.asString(profile?['first_name']) ?? '';
    final String lastName = SqlValue.asString(profile?['last_name']) ?? '';
    final String email = SqlValue.asString(profile?['email']) ?? '';
    final String composed = '$firstName $lastName'.trim();

    return AuthUser(
      id: userId,
      email: email,
      firstName: firstName,
      lastName: lastName,
      displayName: composed.isEmpty ? email : composed,
      phone: SqlValue.asString(profile?['phone']),
      avatarUrl: SqlValue.asString(profile?['avatar_url']),
      permissions: permissions,
      roles: roles,
      school: school == null ? null : _toSchool(school, setupComplete),
      subscription: school == null ? null : _toSubscription(school),
      isSuperAdmin: isSuperAdmin,
      setupComplete: setupComplete,
      mustChangePassword: SqlValue.asBool(profile?['must_change_password']),
    );
  }

  /// `ur.school_id IS NULL` is included deliberately: the platform allows a
  /// role assignment that is not school-scoped, and omitting it would silently
  /// drop permissions for those users.
  Future<List<Role>> _loadRoles(int userId, int schoolId) async {
    final List<Row> rows = await _db.query(
      '''
      SELECT r.id, r.name, r.slug, r.is_super_admin
        FROM user_roles ur
        JOIN roles r ON ur.role_id = r.id
       WHERE ur.user_id = ?
         AND (ur.school_id = ? OR ur.school_id IS NULL)
         AND ur.is_active = TRUE AND r.is_active = TRUE
      ''',
      <Object?>[userId, schoolId],
    );

    return rows
        .map(
          (Row row) => Role(
            id: SqlValue.asInt(row['id']) ?? 0,
            name: SqlValue.asString(row['name']) ?? 'Unknown role',
            slug: SqlValue.asString(row['slug']),
            isSuperAdminFlag: SqlValue.asBool(row['is_super_admin']),
          ),
        )
        .toList(growable: false);
  }

  Future<PermissionSet> _loadPermissions(
    int userId,
    int schoolId,
    bool isSuperAdmin,
  ) async {
    if (isSuperAdmin) return PermissionSet(<String>[PermissionSet.universal]);

    final List<Row> rows = await _db.query(
      '''
      SELECT DISTINCT p.code
        FROM user_roles ur
        JOIN roles r             ON ur.role_id = r.id
        JOIN role_permissions rp ON r.id = rp.role_id
        JOIN permissions p       ON rp.permission_id = p.id
       WHERE ur.user_id = ?
         AND (ur.school_id = ? OR ur.school_id IS NULL)
         AND ur.is_active = TRUE AND r.is_active = TRUE AND p.is_active = TRUE
      ''',
      <Object?>[userId, schoolId],
    );

    return PermissionSet(
      rows.map((Row row) => SqlValue.asString(row['code'])).whereType<String>(),
    );
  }

  SchoolSummary _toSchool(Row school, bool setupComplete) => SchoolSummary(
    id: SqlValue.asInt(school['id'])!,
    name: SqlValue.asString(school['name']) ?? 'Unnamed school',
    email: SqlValue.asString(school['email']),
    phone: SqlValue.asString(school['phone']),
    address: SqlValue.asString(school['address']),
    schoolType: SqlValue.asString(school['school_type']),
    logoUrl: SqlValue.asString(school['logo_url']),
    currency: SqlValue.asString(school['currency']) ?? 'UGX',
    setupComplete: setupComplete,
  );

  SubscriptionStatus _toSubscription(Row school) {
    final DateTime now = DateTime.now();
    final DateTime? subEnd = SqlValue.asDate(school['subscription_end_date']);
    final DateTime? trialEnd = SqlValue.asDate(school['trial_end_date']);
    final DateTime? effective = subEnd ?? trialEnd;
    final int? days = effective?.difference(now).inDays;

    return SubscriptionStatus(
      status: SqlValue.asString(school['subscription_status']) ?? 'unknown',
      hasAccess: !_subscriptionLapsed(school),
      type: SqlValue.asString(school['subscription_type']),
      trialEndDate: trialEnd,
      trialDaysRemaining: trialEnd?.difference(now).inDays,
      subscriptionEndDate: subEnd,
      subscriptionDaysRemaining: subEnd?.difference(now).inDays,
      daysUntilExpiry: days,
      expiringSoon: days != null && days >= 0 && days <= 14,
    );
  }

  /// Mirrors the platform's rule, including the case that matters most: an
  /// **open-ended active** subscription — `active` with no end date — never
  /// counts as expired.
  static bool _subscriptionLapsed(Row school) {
    final String? status = SqlValue.asString(school['subscription_status']);
    if (status == 'expired' || status == 'inactive') return true;

    final DateTime now = DateTime.now();
    final DateTime? subEnd = SqlValue.asDate(school['subscription_end_date']);
    final DateTime? trialEnd = SqlValue.asDate(school['trial_end_date']);

    if (status == 'active' && subEnd != null && subEnd.isBefore(now)) {
      return true;
    }
    if (status == 'trial' && trialEnd != null && trialEnd.isBefore(now)) {
      return true;
    }
    return false;
  }

  /// Creates a `sessions` row and returns its token.
  ///
  /// 32 random bytes hex-encoded — the same shape as the platform's
  /// `randomBytes(32).toString('hex')`, so a session created here is
  /// indistinguishable from one created by the web app.
  Future<String> _createSession(int userId, int? schoolId) async {
    final String token = List<int>.generate(
      32,
      (int _) => _random.nextInt(256),
    ).map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

    await _db.execute(
      '''
      INSERT INTO sessions
        (user_id, school_id, session_token, expires_at,
         device_info, last_activity_at, is_active)
      VALUES (?, ?, ?, ?, ?, NOW(), TRUE)
      ''',
      <Object?>[
        userId,
        schoolId,
        token,
        DateTime.now().add(Duration(days: sessionDays)),
        'DRAIS Mobile / direct',
      ],
    );

    return token;
  }

  Future<void> _clearLocalState() async {
    await _secure.delete(SecureStorageKeys.directSessionToken);
    await _cache.clearAll();
    await _prefs.clearUserScoped();
  }
}
