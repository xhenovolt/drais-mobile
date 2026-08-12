/// A role held by the signed-in user within their school.
///
/// Mirrors a row of `roles` joined through `user_roles`, as returned by
/// `/api/auth/me`.
///
/// ## Super-admin is recognised three ways, deliberately
///
/// LongTerm's session query (`src/lib/auth.ts`) treats a role as super-admin
/// if **any** of the following hold: `is_super_admin = TRUE`, `slug =
/// 'super_admin'`, or the trimmed lowercase name is `super admin` /
/// `superadmin`. The comment there explains why: production roles have
/// historically been created with the boolean forgotten, and the slug is the
/// stable contract. [isSuperAdmin] reproduces that check exactly rather than
/// trusting the flag alone — a client that is stricter than the server will
/// hide functionality the server would have permitted.
class Role {
  /// Creates a role.
  const Role({
    required this.id,
    required this.name,
    this.slug,
    this.isSuperAdminFlag = false,
  });

  /// `roles.id`.
  final int id;

  /// `roles.name`, e.g. "Bursar".
  final String name;

  /// `roles.slug` — the stable identifier. Prefer it over [name] in any
  /// comparison; names are edited by school administrators.
  final String? slug;

  /// The raw `roles.is_super_admin` column.
  final bool isSuperAdminFlag;

  /// Whether this role confers super-admin, using the server's own three-way
  /// test.
  bool get isSuperAdmin {
    if (isSuperAdminFlag) return true;
    if (slug?.toLowerCase() == 'super_admin') return true;
    final String canonical = name.trim().toLowerCase();
    return canonical == 'super admin' || canonical == 'superadmin';
  }

  @override
  String toString() => 'Role($id, $name${slug == null ? '' : ', $slug'})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Role && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
