import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/auth/data/direct/direct_password.dart';

/// Direct mode verifies passwords on the device, so it must read the hashes
/// already in `users` — produced by Node's `bcryptjs` at 12 rounds.
///
/// If this fails, nobody can sign in in direct mode and the whole mode is
/// dead. It is the most important assertion in the direct-mode code.
void main() {
  // Real output of `bcrypt.hashSync('DraisTest!2026', 12)` from the bcryptjs
  // that hashed every existing DRAIS password. 37 of 38 production rows carry
  // the $2b$ prefix, which jBCrypt-derived Dart ports reject unless rewritten.
  const String nodeHash =
      r'$2b$12$AGped4t7.IiDcMKAvtQsY.TIINwHO3jFWZ2fq5T/2TJf4L0RpbQVm';
  const String plaintext = 'DraisTest!2026';

  group('DirectPassword — bcryptjs compatibility', () {
    test('verifies a \$2b\$ hash produced by Node', () {
      expect(DirectPassword.verify(plaintext, nodeHash), isTrue);
    });

    test('rejects the wrong password', () {
      expect(DirectPassword.verify('wrong', nodeHash), isFalse);
      expect(DirectPassword.verify('', nodeHash), isFalse);
    });

    test('round-trips its own hashes', () {
      final String hash = DirectPassword.hash(plaintext);
      expect(DirectPassword.verify(plaintext, hash), isTrue);
      expect(DirectPassword.verify('other', hash), isFalse);
    });

    test('returns false rather than throwing on malformed input', () {
      // A corrupt row must not crash the app or reveal that the account exists.
      expect(DirectPassword.verify(plaintext, null), isFalse);
      expect(DirectPassword.verify(plaintext, ''), isFalse);
      expect(DirectPassword.verify(plaintext, 'not-a-hash'), isFalse);
      expect(DirectPassword.verify(plaintext, r'$2b$12$short'), isFalse);
      expect(DirectPassword.verify(plaintext, r'$1$md5$whatever'), isFalse);
    });
  });
}
