import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';

import 'package:drais_server/db/database.dart';
import 'package:drais_server/http/cookies.dart';

/// The trusted identity behind a request.
///
/// Every field here is derived from the **database session row**, never from
/// anything the client sent. That is the tenant-isolation guarantee: a request
/// cannot widen its own scope, because there is no code path that reads a
/// school id from a body, a query string or a cookie.
class SessionInfo {
  /// Creates a session.
  const SessionInfo({
    required this.userId,
    required this.schoolId,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.isSuperAdmin,
    required this.mustChangePassword,
    this.staffId,
  });

  /// `users.id`.
  final int userId;

  /// **The trusted school id.** The only acceptable source of tenant scope.
  final int schoolId;

  /// `users.email`.
  final String email;

  /// Given name.
  final String firstName;

  /// Family name.
  final String lastName;

  /// Whether any held role confers super-admin.
  final bool isSuperAdmin;

  /// Whether the user must change their password before doing anything else.
  final bool mustChangePassword;

  /// `staff.id`, when this user is linked to a staff record.
  final int? staffId;
}

/// Why a session was refused. Each maps to a different response.
enum SessionRejection {
  /// No cookie was presented.
  missing,

  /// The token does not match a live, unexpired session.
  invalid,

  /// The school row is gone (soft-deleted).
  schoolDeleted,

  /// The school is suspended or archived.
  schoolSuspended,

  /// The subscription or trial has lapsed.
  subscriptionExpired,
}

/// The outcome of resolving a session.
class SessionResult {
  /// A resolved session.
  const SessionResult.ok(this.session) : rejection = null;

  /// A refusal.
  const SessionResult.rejected(this.rejection) : session = null;

  /// The session, when resolved.
  final SessionInfo? session;

  /// Why it was refused, when it was.
  final SessionRejection? rejection;

  /// Whether a session was resolved.
  bool get isOk => session != null;
}

/// Session creation and validation.
///
/// The Dart counterpart of `getSessionSchoolId()` in `src/lib/auth.ts`,
/// including every gate that function applies on **every** request: soft-deleted
/// school, suspended school, lapsed subscription. Those checks are not
/// login-time only, deliberately — a school suspended mid-session loses access
/// on its next request, not at its next login.
abstract final class Session {
  static final Random _random = Random.secure();

  /// Generates a session token.
  ///
  /// 32 bytes of cryptographically secure randomness, hex-encoded to 64
  /// characters — byte-for-byte the same shape as the platform's
  /// `randomBytes(32).toString('hex')`, so existing sessions and new ones are
  /// indistinguishable and either server can validate either.
  static String generateToken() {
    final List<int> bytes =
        List<int>.generate(32, (int _) => _random.nextInt(256));
    return bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Resolves the session behind [request], or explains the refusal.
  static Future<SessionResult> resolve(Database db, Request request) async {
    final String? token = Cookies.read(request, Cookies.session);
    if (token == null || token.isEmpty) {
      return const SessionResult.rejected(SessionRejection.missing);
    }

    final Row? row = await db.queryOne(
      '''
      SELECT
        s.user_id,
        s.school_id,
        u.email,
        u.first_name,
        u.last_name,
        u.must_change_password,
        stf.id                   AS staff_id,
        sc.id                    AS school_row_id,
        sc.status                AS school_status,
        sc.subscription_status   AS subscription_status,
        sc.subscription_end_date AS subscription_end_date,
        sc.trial_end_date        AS trial_end_date,
        EXISTS(
          SELECT 1 FROM user_roles ur
            JOIN roles r ON ur.role_id = r.id
           WHERE ur.user_id = s.user_id
             AND (ur.school_id = s.school_id OR ur.school_id IS NULL)
             AND ur.is_active = TRUE
             AND r.is_active  = TRUE
             AND (
                   r.is_super_admin = TRUE
                OR LOWER(r.slug) = 'super_admin'
                OR LOWER(TRIM(r.name)) IN ('super admin', 'superadmin')
             )
        ) AS is_super_admin
      FROM sessions s
      JOIN users u ON u.id = s.user_id
      LEFT JOIN staff stf
             ON stf.person_id = u.person_id
            AND stf.school_id = s.school_id
            AND stf.deleted_at IS NULL
      LEFT JOIN schools sc ON s.school_id = sc.id AND sc.deleted_at IS NULL
      WHERE s.session_token = ?
        AND s.is_active = TRUE
        AND s.expires_at > NOW()
        AND u.deleted_at IS NULL
      LIMIT 1
      ''',
      <Object?>[token],
    );

    if (row == null) {
      return const SessionResult.rejected(SessionRejection.invalid);
    }

    final int? schoolId = _asInt(row['school_id']);

    // The session names a school that no longer resolves to a live row.
    if (schoolId != null && row['school_row_id'] == null) {
      return const SessionResult.rejected(SessionRejection.schoolDeleted);
    }

    final String? status = row['school_status'] as String?;
    if (status == 'suspended' || status == 'archived') {
      return const SessionResult.rejected(SessionRejection.schoolSuspended);
    }

    if (_subscriptionLapsed(row)) {
      return const SessionResult.rejected(SessionRejection.subscriptionExpired);
    }

    // Touch last_activity_at without blocking the response, and without
    // letting a failure here affect the request. Note this does NOT extend
    // expires_at — the platform has no sliding renewal, and neither does this.
    unawaited(
      db.execute(
        'UPDATE sessions SET last_activity_at = NOW() '
        'WHERE session_token = ? AND is_active = TRUE',
        <Object?>[token],
      ),
    );

    return SessionResult.ok(
      SessionInfo(
        userId: _asInt(row['user_id']) ?? 0,
        schoolId: schoolId ?? 0,
        email: row['email'] as String? ?? '',
        firstName: row['first_name'] as String? ?? '',
        lastName: row['last_name'] as String? ?? '',
        isSuperAdmin: _asBool(row['is_super_admin']),
        mustChangePassword: _asBool(row['must_change_password']),
        staffId: _asInt(row['staff_id']),
      ),
    );
  }

  /// Creates a session row and returns its token.
  static Future<String> create(
    Database db, {
    required int userId,
    required int? schoolId,
    required int days,
    String? ipAddress,
    String? userAgent,
  }) async {
    final String token = generateToken();
    final DateTime expiresAt = DateTime.now().add(Duration(days: days));

    await db.execute(
      '''
      INSERT INTO sessions
        (user_id, school_id, session_token, expires_at,
         ip_address, user_agent, device_info, last_activity_at, is_active)
      VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), TRUE)
      ''',
      <Object?>[
        userId,
        schoolId,
        token,
        expiresAt,
        ipAddress,
        userAgent,
        userAgent == null ? null : describeDevice(userAgent),
      ],
    );

    return token;
  }

  /// Marks a session inactive.
  static Future<void> invalidate(Database db, String token) => db.execute(
        'UPDATE sessions SET is_active = FALSE, updated_at = NOW() '
        'WHERE session_token = ?',
        <Object?>[token],
      );

  /// Summarises a User-Agent for `sessions.device_info`.
  ///
  /// Mirrors the platform's parser, and recognises the Flutter client's own
  /// `DRAISMobile/1.0.0` agent so mobile sessions are identifiable in the
  /// user's device list rather than showing as "Unknown".
  static String describeDevice(String userAgent) {
    if (userAgent.startsWith('DRAISMobile')) {
      final Match? version =
          RegExp(r'DRAISMobile/([\d.]+)').firstMatch(userAgent);
      return 'DRAIS Mobile ${version?.group(1) ?? ''} / App'.trim();
    }

    String browser = 'Unknown';
    String os = 'Unknown';
    String device = 'Desktop';

    if (userAgent.contains('Edg/')) {
      browser = 'Edge';
    } else if (userAgent.contains('Chrome/')) {
      browser = 'Chrome';
    } else if (userAgent.contains('Firefox/')) {
      browser = 'Firefox';
    } else if (userAgent.contains('Safari/')) {
      browser = 'Safari';
    }

    if (userAgent.contains('Android')) {
      os = 'Android';
      device = 'Mobile';
    } else if (userAgent.contains('iPhone') || userAgent.contains('iPad')) {
      os = 'iOS';
      device = userAgent.contains('iPad') ? 'Tablet' : 'Mobile';
    } else if (userAgent.contains('Windows')) {
      os = 'Windows';
    } else if (userAgent.contains('Mac OS')) {
      os = 'macOS';
    } else if (userAgent.contains('Linux')) {
      os = 'Linux';
    }

    final String summary = '$browser / $os / $device';
    return summary.length > 500 ? summary.substring(0, 500) : summary;
  }

  /// Whether the school's access has lapsed.
  ///
  /// Mirrors the platform's rule exactly, including the case that matters
  /// most: an **open-ended active** subscription — `active` with no end date —
  /// is never treated as expired.
  static bool _subscriptionLapsed(Row row) {
    final String? status = row['subscription_status'] as String?;
    if (status == 'expired' || status == 'inactive') return true;

    final DateTime now = DateTime.now();
    final DateTime? subEnd = _asDate(row['subscription_end_date']);
    final DateTime? trialEnd = _asDate(row['trial_end_date']);

    if (status == 'active' && subEnd != null && subEnd.isBefore(now)) {
      return true;
    }
    if (status == 'trial' && trialEnd != null && trialEnd.isBefore(now)) {
      return true;
    }
    return false;
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

/// Fire-and-forget helper for the non-blocking activity update.
void unawaited(Future<void> future) {
  future.catchError((Object _) {});
}

/// Extracts the client IP, honouring the proxy headers a hosted deployment sets.
String? clientIp(Request request) {
  final String? forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  return request.headers['x-real-ip'];
}

/// JSON encoder shared by route handlers.
const JsonEncoder jsonOut = JsonEncoder();
