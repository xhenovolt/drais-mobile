import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/database/drais_database.dart';

/// MySQL/TiDB values do not arrive as one predictable Dart type, and guessing
/// wrong is silent.
///
/// The case that actually shipped a bug: `users.is_active` is `tinyint(1)`,
/// and `mysql_client` returns it as a Dart **bool**. Reading it as an int
/// yields null. Defaulting that null to 0 rejected every active user with
/// "your account is pending approval"; comparing it to 0 without a default
/// does the opposite and lets a deactivated account sign in.
void main() {
  group('SqlValue.asBool — tinyint(1) arrives in several shapes', () {
    test('reads a native bool, which is what the driver returns', () {
      expect(SqlValue.asBool(true), isTrue);
      expect(SqlValue.asBool(false), isFalse);
    });

    test('reads 0/1 integers', () {
      expect(SqlValue.asBool(1), isTrue);
      expect(SqlValue.asBool(0), isFalse);
    });

    test("reads '0'/'1' strings", () {
      expect(SqlValue.asBool('1'), isTrue);
      expect(SqlValue.asBool('true'), isTrue);
      expect(SqlValue.asBool('0'), isFalse);
      expect(SqlValue.asBool('false'), isFalse);
    });

    test('treats null as false', () {
      // Safe direction: a missing flag denies rather than grants.
      expect(SqlValue.asBool(null), isFalse);
    });
  });

  group('SqlValue.asInt', () {
    test('reads ints, numeric strings and nulls', () {
      expect(SqlValue.asInt(42), 42);
      expect(SqlValue.asInt('42'), 42);
      expect(SqlValue.asInt(null), isNull);
      expect(SqlValue.asInt('not a number'), isNull);
    });

    test('returns null for a bool — the trap', () {
      // This is why `asInt(is_active) ?? 0` rejected every active user.
      expect(SqlValue.asInt(true), isNull);
      expect(SqlValue.asInt(false), isNull);
    });
  });

  group('SqlValue.asDate', () {
    test('reads DateTime and ISO strings', () {
      final DateTime now = DateTime(2026, 8, 6);
      expect(SqlValue.asDate(now), now);
      expect(SqlValue.asDate('2026-08-06'), DateTime(2026, 8, 6));
      expect(SqlValue.asDate(null), isNull);
      expect(SqlValue.asDate('rubbish'), isNull);
    });
  });

  group('DraisDatabase.limitClause', () {
    test('emits literal integers, never bound parameters', () {
      expect(DraisDatabase.limitClause(limit: 25), 'LIMIT 25 OFFSET 0');
      expect(
        DraisDatabase.limitClause(limit: 50, offset: 100),
        'LIMIT 50 OFFSET 100',
      );
    });

    test('clamps out-of-range values', () {
      expect(DraisDatabase.limitClause(limit: 0), contains('LIMIT 1'));
      expect(DraisDatabase.limitClause(limit: 99999), contains('LIMIT 500'));
      expect(
        DraisDatabase.limitClause(limit: 10, offset: -5),
        contains('OFFSET 0'),
      );
    });
  });
}
