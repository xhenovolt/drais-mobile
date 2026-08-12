import 'package:dbcrypt/dbcrypt.dart';

/// bcrypt verification for direct mode.
///
/// ## Compatibility is the requirement
///
/// Existing passwords were hashed by Node's `bcryptjs` at 12 rounds. This must
/// verify those hashes exactly; a migration forcing every user to reset would
/// be a far worse outcome than keeping the server.
///
/// **`$2b$` is rewritten to `$2a$` before checking.** `bcryptjs` emits `$2b$`
/// (37 of 38 rows in production), while `dbcrypt` — a jBCrypt port — accepts
/// `$2a$` and `$2y$` but rejects `$2b$` outright. The prefixes are
/// verification-compatible: `$2b$` fixed a bug in some C implementations
/// handling passwords over 255 bytes, and the algorithm is otherwise
/// identical. Verified against a real `bcryptjs` hash in
/// `test/features/auth/direct_password_test.dart`.
abstract final class DirectPassword {
  /// Work factor for new hashes, matching `BCRYPT_ROUNDS=12`.
  static const int rounds = 12;

  /// Verifies [plaintext] against a stored hash.
  ///
  /// Returns false for anything malformed rather than throwing: a corrupt row
  /// must not become a crash that reveals the account exists.
  static bool verify(String plaintext, String? hash) {
    if (hash == null || hash.isEmpty) return false;

    final String normalised = hash.startsWith(r'$2b$')
        ? '\$2a\$${hash.substring(4)}'
        : hash;

    if (!RegExp(r'^\$2[aby]\$\d{2}\$.{53}$').hasMatch(normalised)) return false;

    try {
      return DBCrypt().checkpw(plaintext, normalised);
    } on Object {
      return false;
    }
  }

  /// Hashes a new password at [rounds].
  static String hash(String plaintext) =>
      DBCrypt().hashpw(plaintext, DBCrypt().gensaltWithRounds(rounds));
}
