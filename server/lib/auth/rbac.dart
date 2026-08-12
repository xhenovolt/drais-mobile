import 'package:drais_server/db/database.dart';

/// A role held by a user in a school.
class RoleRecord {
  /// Creates a role record.
  const RoleRecord({
    required this.id,
    required this.name,
    this.slug,
    this.isSuperAdminFlag = false,
  });

  /// `roles.id`.
  final int id;

  /// `roles.name`, editable by school administrators.
  final String name;

  /// `roles.slug` — the stable identifier.
  final String? slug;

  /// The raw `roles.is_super_admin` column.
  final bool isSuperAdminFlag;

  /// Whether this role confers super-admin.
  ///
  /// Reproduces the platform's three-way test from `src/lib/auth.ts`. The
  /// comment there explains why it is not simply the boolean: production roles
  /// have been created with the flag forgotten, and the slug is the canonical
  /// contract. Being stricter than the platform would lock real
  /// administrators out of their own schools.
  bool get isSuperAdmin {
    if (isSuperAdminFlag) return true;
    if (slug?.toLowerCase() == 'super_admin') return true;
    final String canonical = name.trim().toLowerCase();
    return canonical == 'super admin' || canonical == 'superadmin';
  }

  /// The JSON shape `/api/auth/me` returns.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'slug': slug,
        'isSuperAdmin': isSuperAdmin,
      };
}

/// Role and permission loading.
///
/// Mirrors the permission model in `src/lib/rbac.ts`:
/// `user → user_roles → roles → role_permissions → permissions`.
abstract final class Rbac {
  /// The grant returned to a super-admin, which satisfies every check.
  static const String universalGrant = '*';

  /// Loads the roles a user holds in a school.
  ///
  /// `ur.school_id IS NULL` is included deliberately: the platform permits a
  /// role assignment that is not school-scoped, and omitting it would silently
  /// drop permissions for those users.
  static Future<List<RoleRecord>> rolesFor(
    Database db, {
    required int userId,
    required int schoolId,
  }) async {
    final List<Row> rows = await db.query(
      '''
      SELECT r.id, r.name, r.slug, r.is_super_admin
        FROM user_roles ur
        JOIN roles r ON ur.role_id = r.id
       WHERE ur.user_id = ?
         AND (ur.school_id = ? OR ur.school_id IS NULL)
         AND ur.is_active = TRUE
         AND r.is_active  = TRUE
      ''',
      <Object?>[userId, schoolId],
    );

    return rows
        .map(
          (Row row) => RoleRecord(
            id: _asInt(row['id']) ?? 0,
            name: row['name'] as String? ?? 'Unknown role',
            slug: row['slug'] as String?,
            isSuperAdminFlag: _asBool(row['is_super_admin']),
          ),
        )
        .toList(growable: false);
  }

  /// Loads the permission codes a user holds.
  ///
  /// A super-admin gets `['*']` without a permissions join, matching what the
  /// platform returns — and matching what the Flutter client's `PermissionSet`
  /// already understands as the universal grant.
  static Future<List<String>> permissionsFor(
    Database db, {
    required int userId,
    required int schoolId,
    required bool isSuperAdmin,
  }) async {
    if (isSuperAdmin) return const <String>[universalGrant];

    final List<Row> rows = await db.query(
      '''
      SELECT DISTINCT p.code
        FROM user_roles ur
        JOIN roles r            ON ur.role_id = r.id
        JOIN role_permissions rp ON r.id = rp.role_id
        JOIN permissions p       ON rp.permission_id = p.id
       WHERE ur.user_id = ?
         AND (ur.school_id = ? OR ur.school_id IS NULL)
         AND ur.is_active = TRUE
         AND r.is_active  = TRUE
         AND p.is_active  = TRUE
      ''',
      <Object?>[userId, schoolId],
    );

    return rows
        .map((Row row) => row['code'] as String?)
        .whereType<String>()
        .toList(growable: false);
  }

  /// Expands a permission code into every grant that would satisfy it.
  ///
  /// `academics.results.update` → itself, `academics.results.*`,
  /// `academics.*`, `*`. Mirrors `expandPermissionChain()` in
  /// `src/lib/rbac/catalog.ts`, and is the exact twin of `PermissionSet`
  /// in the Flutter client. All three must agree.
  static List<String> expandChain(String code) {
    final String needle = code.trim().toLowerCase();
    if (needle.isEmpty) return const <String>[];

    final List<String> chain = <String>[needle];
    final List<String> segments = needle.split('.');
    for (int i = segments.length - 1; i > 0; i--) {
      chain.add('${segments.take(i).join('.')}.*');
    }
    chain.add(universalGrant);
    return chain;
  }

  /// Whether [granted] satisfies a request for [code].
  static bool allows(Iterable<String> granted, String code) {
    final Set<String> held =
        granted.map((String c) => c.trim().toLowerCase()).toSet();
    return expandChain(code).any(held.contains);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// MySQL `TINYINT(1)` arrives as an int through some driver paths and as a
  /// bool through others, so both are accepted.
  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final String v = value.trim().toLowerCase();
      return v == '1' || v == 'true';
    }
    return false;
  }
}
