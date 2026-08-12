import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/logging/redaction.dart';

/// Redaction is a security control, so it is tested like one.
///
/// A `drais_session` value is a seven-day bearer credential. If any of these
/// tests start failing, a live credential is reaching the log — treat it as an
/// incident, not a test failure.
void main() {
  group('scrubText', () {
    test('masks the session cookie value', () {
      const String line =
          'Cookie: drais_session=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4; Path=/';

      final String scrubbed = Redaction.scrubText(line);

      expect(scrubbed, contains('drais_session=***'));
      expect(scrubbed, isNot(contains('a1b2c3d4e5f6')));
    });

    test('masks every DRAIS auth cookie, not just the session', () {
      const String line =
          'drais_school_id=42; drais_role=Bursar; drais_force_reset=1';

      final String scrubbed = Redaction.scrubText(line);

      expect(scrubbed, isNot(contains('Bursar')));
      expect(scrubbed, contains('drais_role=***'));
    });

    test('masks bearer tokens', () {
      final String scrubbed = Redaction.scrubText(
        'Authorization: Bearer abc123def456ghi789',
      );

      expect(scrubbed, isNot(contains('abc123def456')));
    });

    test('masks a password inside a JSON fragment', () {
      final String scrubbed = Redaction.scrubText(
        '{"email":"a@b.co","password":"hunter2"}',
      );

      expect(scrubbed, isNot(contains('hunter2')));
    });

    test('masks a bare 64-character hex session token', () {
      // randomBytes(32).toString('hex') in /api/auth/login.
      final String token = 'de' * 32;

      expect(Redaction.scrubText('token=$token'), isNot(contains(token)));
    });

    test('partially masks an email, keeping it recognisable', () {
      // Knowing *which* account failed to sign in is the point of the log
      // line; the full address is not needed to answer that.
      final String scrubbed = Redaction.scrubText(
        'login failed for teacher@school.ug',
      );

      expect(scrubbed, contains('t***@school.ug'));
      expect(scrubbed, isNot(contains('teacher@')));
    });

    test('leaves innocuous text untouched', () {
      const String line = 'Loaded 24 students for class P5';

      expect(Redaction.scrubText(line), line);
    });
  });

  group('scrubMap', () {
    test('masks values under sensitive keys', () {
      final Map<String, Object?> scrubbed =
          Redaction.scrubMap(<String, Object?>{
            'email': 'a@b.co',
            'password': 'hunter2',
            'sessionToken': 'abc',
            'apiKey': 'xyz',
            'count': 12,
          });

      expect(scrubbed['password'], Redaction.mask);
      expect(scrubbed['sessionToken'], Redaction.mask);
      expect(scrubbed['apiKey'], Redaction.mask);
      expect(scrubbed['count'], 12);
    });

    test('matches sensitive keys regardless of separators or case', () {
      final Map<String, Object?> scrubbed =
          Redaction.scrubMap(<String, Object?>{
            'X-Session-Token': 'abc',
            'refresh_token': 'def',
            'PASSWORD_CONFIRMATION': 'ghi',
          });

      expect(scrubbed.values, everyElement(Redaction.mask));
    });

    test('keeps allowlisted keys that only look sensitive', () {
      final Map<String, Object?> scrubbed = Redaction.scrubMap(
        <String, Object?>{
          'authenticated': true,
          'session_expired': false,
          'token_present': true,
        },
      );

      expect(scrubbed['authenticated'], isTrue);
      expect(scrubbed['session_expired'], isFalse);
      expect(scrubbed['token_present'], isTrue);
    });

    test('recurses into nested maps and lists', () {
      final Map<String, Object?> scrubbed = Redaction.scrubMap(
        <String, Object?>{
          'request': <String, Object?>{
            'headers': <String, Object?>{'cookie': 'drais_session=abc'},
          },
          'attempts': <Object?>[
            <String, Object?>{'password': 'hunter2'},
          ],
        },
      );

      // `headers` is not itself a sensitive key, so the scrubber descends into
      // it and masks the `cookie` entry rather than blanking the whole map.
      final Map<String, Object?> request =
          scrubbed['request']! as Map<String, Object?>;
      final Map<String, Object?> headers =
          request['headers']! as Map<String, Object?>;
      expect(headers['cookie'], Redaction.mask);

      final List<Object?> attempts = scrubbed['attempts']! as List<Object?>;
      final Map<String, Object?> first =
          attempts.first! as Map<String, Object?>;
      expect(first['password'], Redaction.mask);
    });
  });
}
