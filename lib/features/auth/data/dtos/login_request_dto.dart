/// The request body for `POST /api/auth/login`.
///
/// The backend reads exactly two fields, `email` and `password`
/// (`src/app/api/auth/login/route.ts`). Nothing else is sent — a client that
/// invents fields the server ignores creates the false impression of a
/// contract that does not exist.
class LoginRequestDto {
  /// Creates a login request.
  const LoginRequestDto({required this.email, required this.password});

  /// Login identifier. Trimmed and lowercased before sending.
  ///
  /// The backend matches `users.email` with a plain SQL `=`, which is
  /// case-insensitive under MySQL's default collation — but the audit log
  /// records `String(email).toLowerCase()`, so normalising here keeps the
  /// audit trail consistent regardless of how the user typed it.
  final String email;

  /// Plaintext password, compared server-side with `bcrypt.compare`.
  ///
  /// Never logged, never cached, never written to storage. The redaction rules
  /// in `lib/core/logging/redaction.dart` mask it even if some future code
  /// path passes this object to a logger.
  final String password;

  /// Renders the JSON body.
  Map<String, Object?> toJson() => <String, Object?>{
    'email': email.trim().toLowerCase(),
    'password': password,
  };

  /// Never includes the password.
  @override
  String toString() => 'LoginRequestDto(email: ${email.trim()})';
}

/// The request body for `POST /api/auth/change-password`.
class ChangePasswordRequestDto {
  /// Creates a change-password request.
  const ChangePasswordRequestDto({
    required this.currentPassword,
    required this.newPassword,
  });

  /// The existing password, re-verified server-side.
  final String currentPassword;

  /// The replacement. Policy (length, complexity) is enforced by the server;
  /// the client only pre-checks the obvious to save a round trip.
  final String newPassword;

  /// Renders the JSON body.
  Map<String, Object?> toJson() => <String, Object?>{
    'currentPassword': currentPassword,
    'newPassword': newPassword,
  };

  /// Never includes either password.
  @override
  String toString() => 'ChangePasswordRequestDto()';
}
