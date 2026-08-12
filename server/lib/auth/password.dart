import 'package:dbcrypt/dbcrypt.dart';

/// Password verification against hashes produced by DRAIS LongTerm.
///
/// ## Compatibility is the whole requirement
///
/// Existing users' passwords were hashed by Node's `bcryptjs` with
/// `BCRYPT_ROUNDS=12`. This server must verify those hashes exactly — a
/// migration that forced every user to reset their password would be a far
/// worse outcome than keeping Node.
///
/// ### The `$2a$` / `$2b$` prefix
///
/// bcrypt hashes carry a version prefix. `bcryptjs` emits `$2a$` or `$2b$`
/// depending on version; `dbcrypt` is a port of jBCrypt, which recognises
/// `$2a$` and `$2y$` but rejects `$2b$` outright.
///
/// The prefixes are **verification-compatible**: `$2b$` was introduced to fix
/// a bug in some C implementations handling passwords over 255 bytes, and the
/// algorithm is otherwise identical. So a `$2b$` hash is rewritten to `$2a$`
/// before checking. This is safe for every password of sane length, and DRAIS
/// has no password approaching 255 bytes.
///
/// This is exactly the kind of detail that decides whether a rewrite works,
/// and it is why the first thing to test against production is a real login.
abstract final class Password {
  /// Work factor for newly-hashed passwords. Matches `BCRYPT_ROUNDS=12`.
  static const int rounds = 12;

  /// Verifies [plaintext] against a stored bcrypt [hash].
  ///
  /// Returns false for anything malformed rather than throwing: a corrupt
  /// hash in one row must not turn into a 500 that tells an attacker the row
  /// exists.
  static bool verify(String plaintext, String? hash) {
    if (hash == null || hash.isEmpty) return false;

    final String normalised = _normalisePrefix(hash);
    if (!_looksLikeBcrypt(normalised)) return false;

    try {
      return DBCrypt().checkpw(plaintext, normalised);
    } on Object {
      // Malformed salt, unsupported prefix, truncated hash.
      return false;
    }
  }

  /// Hashes a new password at [rounds].
  static String hash(String plaintext) =>
      DBCrypt().hashpw(plaintext, DBCrypt().gensaltWithRounds(rounds));

  /// Rewrites a `$2b$` prefix to `$2a$` for verification. See the class docs.
  static String _normalisePrefix(String hash) =>
      hash.startsWith(r'$2b$') ? '\$2a\$${hash.substring(4)}' : hash;

  /// Whether a string has the shape of a bcrypt hash: `$2x$NN$` + 53 chars.
  static bool _looksLikeBcrypt(String hash) =>
      RegExp(r'^\$2[aby]\$\d{2}\$.{53}$').hasMatch(hash);
}
