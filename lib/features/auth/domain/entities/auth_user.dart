import 'package:drais/features/auth/domain/entities/permission_set.dart';
import 'package:drais/features/auth/domain/entities/role.dart';
import 'package:drais/features/auth/domain/entities/school_summary.dart';
import 'package:drais/features/auth/domain/entities/subscription_status.dart';

/// The signed-in user, their tenant, and what they are allowed to do.
///
/// Assembled from `/api/auth/me`, which is the richer of the two sources —
/// `/api/auth/login` returns a thinner object (roles as bare strings, no
/// school detail, no subscription block). The app therefore treats login as
/// *"establish the session"* and `/api/auth/me` as *"load the identity"*,
/// calling the second immediately after the first. That also means session
/// restoration and sign-in converge on one code path, so there is only one
/// place identity can be assembled wrongly.
class AuthUser {
  /// Creates an authenticated user.
  const AuthUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.permissions,
    required this.roles,
    this.phone,
    this.avatarUrl,
    this.school,
    this.subscription,
    this.isSuperAdmin = false,
    this.setupComplete = true,
    this.mustChangePassword = false,
  });

  /// `users.id`.
  final int id;

  /// `users.email` — the login identifier.
  final String email;

  /// Given name.
  final String firstName;

  /// Family name.
  final String lastName;

  /// Server-composed display name, falling back to the email.
  final String displayName;

  /// Granted permissions, wildcard-aware.
  final PermissionSet permissions;

  /// Roles held in this school.
  final List<Role> roles;

  /// Contact phone.
  final String? phone;

  /// Profile image URL.
  final String? avatarUrl;

  /// The tenant. Null only for a user not yet attached to a school.
  final SchoolSummary? school;

  /// Subscription state, when the backend reported it.
  final SubscriptionStatus? subscription;

  /// Whether the server considers this user a super-admin.
  ///
  /// Trust this over any local inspection of [roles]: the server's test also
  /// covers Control Center impersonation, which sets no role at all and which
  /// the client cannot detect (ADR-0008).
  final bool isSuperAdmin;

  /// Whether school setup is finished. False sends the user to the web app.
  final bool setupComplete;

  /// Whether `users.must_change_password` is set. The backend redirects the
  /// web app to a forced reset; mobile must gate navigation the same way.
  final bool mustChangePassword;

  /// The tenant id, or null. Informational only — see [SchoolSummary].
  int? get schoolId => school?.id;

  /// Initials for an avatar placeholder.
  String get initials {
    final String a = firstName.trim().isNotEmpty ? firstName.trim()[0] : '';
    final String b = lastName.trim().isNotEmpty ? lastName.trim()[0] : '';
    final String combined = '$a$b'.trim();
    return combined.isEmpty
        ? email.substring(0, email.isEmpty ? 0 : 1).toUpperCase()
        : combined.toUpperCase();
  }

  /// Whether the user may reach the main application.
  ///
  /// Two things genuinely bar entry: a forced password change, and lapsed
  /// access. Both are unrecoverable from inside the app.
  ///
  /// **Incomplete setup deliberately does not.** A school that has just
  /// registered on a phone is allowed in to look around; the home screen
  /// carries a banner naming what is still missing, and setup stays one tap
  /// away. Locking them out would make the first thing DRAIS ever asks of them
  /// a chore, and some of them are planning to configure on a computer anyway.
  ///
  /// Still a **UX courtesy, not a security control** — the server applies its
  /// own gates regardless, and in API mode a setup-incomplete school will get
  /// `SETUP_INCOMPLETE` from routes that need it. The app simply stops
  /// pre-emptively refusing.
  bool get canEnterApp =>
      !mustChangePassword && (subscription?.hasAccess ?? true);

  /// Whether the school still needs configuring before attendance works.
  bool get needsSetup => !setupComplete;

  /// Whether the user holds [code], honouring wildcards and super-admin.
  bool can(String code) => isSuperAdmin || permissions.allows(code);

  /// Whether the user holds every code in [codes].
  bool canAll(Iterable<String> codes) => codes.every(can);

  /// Whether the user holds at least one of [codes].
  bool canAny(Iterable<String> codes) => codes.any(can);

  /// Returns a copy with the given overrides.
  AuthUser copyWith({
    PermissionSet? permissions,
    List<Role>? roles,
    SchoolSummary? school,
    SubscriptionStatus? subscription,
    bool? mustChangePassword,
    bool? setupComplete,
  }) => AuthUser(
    id: id,
    email: email,
    firstName: firstName,
    lastName: lastName,
    displayName: displayName,
    permissions: permissions ?? this.permissions,
    roles: roles ?? this.roles,
    phone: phone,
    avatarUrl: avatarUrl,
    school: school ?? this.school,
    subscription: subscription ?? this.subscription,
    isSuperAdmin: isSuperAdmin,
    setupComplete: setupComplete ?? this.setupComplete,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
  );

  @override
  String toString() =>
      'AuthUser($id, $email, school: ${school?.id}, '
      'roles: ${roles.length}, superAdmin: $isSuperAdmin)';
}
