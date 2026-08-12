import 'package:drais/features/auth/domain/entities/auth_user.dart';
import 'package:drais/features/auth/domain/entities/permission_set.dart';
import 'package:drais/features/auth/domain/entities/role.dart';
import 'package:drais/features/auth/domain/entities/school_summary.dart';
import 'package:drais/features/auth/domain/entities/subscription_status.dart';

/// Parses the `user` object returned by `/api/auth/me` and `/api/auth/login`.
///
/// ## Why this is hand-written
///
/// Code generation (`json_serializable` / `freezed`) is the reflex choice, and
/// it is the wrong one here. The two auth endpoints return **different shapes
/// for the same field**: `/api/auth/me` sends `roles` as objects
/// (`{id, name, slug, isSuperAdmin}`), while `/api/auth/login` sends bare
/// strings (`['Bursar']`). A generated parser handles one and throws on the
/// other. Every such quirk would need a custom converter anyway, at which
/// point the generator adds a build step and hides the interesting logic.
///
/// Hand-written parsing keeps every accommodation visible, documented, and
/// attributable to a line in the backend. That is worth more over a decade
/// than the typing it saves. Recorded in
/// `docs/adr/M0005-hand-written-serialization.md`.
///
/// ## Defensive by policy
///
/// Missing optional fields yield sensible defaults; a missing **required**
/// field throws, which the API client converts into a
/// `MalformedResponseFailure` naming a contract drift. Silently defaulting an
/// absent `id` to `0` would push the failure somewhere far away from its
/// cause.
abstract final class AuthUserDto {
  /// Builds an [AuthUser] from a decoded `user` object.
  ///
  /// [setupComplete] and [mustChangePassword] are passed separately because
  /// both endpoints report them at the **top level** of the response, outside
  /// the `user` object — while `/api/auth/login` *also* repeats them inside
  /// it. The top-level value wins.
  static AuthUser fromJson(
    Map<String, Object?> json, {
    bool? setupComplete,
    bool? mustChangePassword,
  }) {
    final int id = _requireInt(json, 'id');
    final String email = _string(json['email']) ?? '';
    final String firstName = _string(json['firstName']) ?? '';
    final String lastName = _string(json['lastName']) ?? '';

    return AuthUser(
      id: id,
      email: email,
      firstName: firstName,
      lastName: lastName,
      displayName: _string(json['displayName'])?.trim().isNotEmpty ?? false
          ? _string(json['displayName'])!.trim()
          : _fallbackDisplayName(firstName, lastName, email),
      phone: _string(json['phone']),
      avatarUrl: _string(json['avatarUrl']),
      permissions: _parsePermissions(json['permissions']),
      roles: _parseRoles(json['roles']),
      school: _parseSchool(json),
      subscription: _parseSubscription(json['subscription']),
      isSuperAdmin: _bool(json['isSuperAdmin']) ?? false,
      setupComplete: setupComplete ?? _bool(json['setupComplete']) ?? true,
      mustChangePassword:
          mustChangePassword ?? _bool(json['mustChangePassword']) ?? false,
    );
  }

  // ── Roles ──────────────────────────────────────────────────────────────

  /// Parses both role shapes the backend emits.
  ///
  /// * `/api/auth/me`: `[{id, name, slug, isSuperAdmin}, …]`
  /// * `/api/auth/login`: `['Bursar', 'Class Teacher']`
  ///
  /// String-shaped roles carry no id, so a negative synthetic id is assigned.
  /// It never collides with a real `roles.id` and makes the provenance obvious
  /// in a debugger — which matters, because a role parsed from the login
  /// response has no slug and must not be compared by name.
  static List<Role> _parseRoles(Object? raw) {
    if (raw is! List) return const <Role>[];

    final List<Role> roles = <Role>[];
    for (int i = 0; i < raw.length; i++) {
      final Object? entry = raw[i];
      if (entry is String) {
        roles.add(Role(id: -(i + 1), name: entry));
      } else if (entry is Map) {
        final Map<String, Object?> json = entry.map(
          (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
        );
        roles.add(
          Role(
            id: _int(json['id']) ?? -(i + 1),
            name: _string(json['name']) ?? 'Unknown role',
            slug: _string(json['slug']),
            isSuperAdminFlag: _bool(json['isSuperAdmin']) ?? false,
          ),
        );
      }
    }
    return List<Role>.unmodifiable(roles);
  }

  // ── Permissions ────────────────────────────────────────────────────────

  /// Parses `permissions`, which is `['*']` for super-admins and a list of
  /// `permissions.code` values otherwise.
  static PermissionSet _parsePermissions(Object? raw) {
    if (raw is! List) return PermissionSet.empty;
    return PermissionSet(raw.whereType<String>());
  }

  // ── School ─────────────────────────────────────────────────────────────

  /// Parses the school, from either the nested `school` object
  /// (`/api/auth/me`) or the flat `schoolId`/`schoolName` pair
  /// (`/api/auth/login`).
  static SchoolSummary? _parseSchool(Map<String, Object?> json) {
    final Object? nested = json['school'];
    if (nested is Map) {
      final Map<String, Object?> school = nested.map(
        (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
      );
      final int? id = _int(school['id']);
      if (id == null) return null;
      return SchoolSummary(
        id: id,
        name: _string(school['name']) ?? 'Unnamed school',
        email: _string(school['email']),
        phone: _string(school['phone']),
        address: _string(school['address']),
        schoolType: _string(school['schoolType']),
        logoUrl: _string(school['logoUrl']),
        currency: _string(school['currency']) ?? 'UGX',
        setupComplete: _bool(school['setupComplete']) ?? true,
      );
    }

    final int? flatId = _int(json['schoolId']);
    if (flatId == null) return null;
    return SchoolSummary(
      id: flatId,
      name: _string(json['schoolName']) ?? 'Unnamed school',
    );
  }

  // ── Subscription ───────────────────────────────────────────────────────

  static SubscriptionStatus? _parseSubscription(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, Object?> json = raw.map(
      (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
    );

    return SubscriptionStatus(
      status: _string(json['status']) ?? 'unknown',
      // Absent `hasAccess` defaults to true: the request that returned this
      // body succeeded, so the server evidently granted access. Defaulting to
      // false would lock out a working account over a missing field.
      hasAccess: _bool(json['hasAccess']) ?? true,
      type: _string(json['type']),
      trialEndDate: _dateTime(json['trialEndDate']),
      trialDaysRemaining: _int(json['trialDaysRemaining']),
      subscriptionEndDate: _dateTime(json['subscriptionEndDate']),
      subscriptionDaysRemaining: _int(json['subscriptionDaysRemaining']),
      daysUntilExpiry: _int(json['daysUntilExpiry']),
      expiringSoon: _bool(json['expiringSoon']) ?? false,
    );
  }

  // ── Primitive coercion ─────────────────────────────────────────────────
  //
  // MySQL/TiDB returns BIGINT columns as strings through some driver paths,
  // and TINYINT(1) booleans arrive as 0/1. The backend's JSON serialisation
  // mostly normalises this, but not everywhere — so coerce rather than cast.

  static String? _string(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  static int? _int(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static bool? _bool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String v = value.trim().toLowerCase();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    return null;
  }

  static DateTime? _dateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int _requireInt(Map<String, Object?> json, String key) {
    final int? value = _int(json[key]);
    if (value == null) {
      throw FormatException(
        'Required field "$key" is missing or not numeric in the user payload. '
        'This means the DRAIS API contract has changed — see docs/PARITY.md.',
        json.toString(),
      );
    }
    return value;
  }

  static String _fallbackDisplayName(
    String firstName,
    String lastName,
    String email,
  ) {
    final String composed = '$firstName $lastName'.trim();
    return composed.isEmpty ? email : composed;
  }
}
