import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/features/attendance/data/direct/longterm/gender_filter.dart';
import 'package:drais/features/attendance/data/direct/longterm/school_time.dart';

/// School-local day windows over UTC `punch_at`.
///
/// The bug these guard against is the one LongTerm's `dashboard-counts.ts`
/// names: `DATE(punch_at)` puts every punch between 00:00 and 02:59 EAT on
/// the previous day.
void main() {
  group('day boundaries in EAT (+180)', () {
    test('a school day starts at 21:00 UTC the evening before', () {
      expect(
        toUtcBoundary('2026-09-29', end: false, offsetMinutes: 180),
        '2026-09-28 21:00:00',
      );
      expect(utcDayStart('2026-09-29', 180), '2026-09-28 21:00:00');
    });

    test('and ends at 20:59:59 UTC', () {
      expect(
        toUtcBoundary('2026-09-29', end: true, offsetMinutes: 180),
        '2026-09-29 20:59:59',
      );
      expect(utcDayStart('2026-09-29', 180, 1), '2026-09-29 21:00:00');
    });

    test('the morning window includes the whole of 11:59', () {
      expect(
        timeBoundary(
          '2026-09-29',
          '05:00',
          endOfMinute: false,
          offsetMinutes: 180,
        ),
        '2026-09-29 02:00:00',
      );
      expect(
        timeBoundary(
          '2026-09-29',
          '11:59',
          endOfMinute: true,
          offsetMinutes: 180,
        ),
        '2026-09-29 08:59:59',
      );
    });
  });

  group('late cutoff arithmetic', () {
    test('adds the threshold to arrival end', () {
      expect(addMinutesToTime('08:30:00', 15), '08:45:00');
    });
    test('wraps past midnight', () {
      expect(addMinutesToTime('23:50:00', 20), '00:10:00');
    });
    test('a missing arrival end reads as the platform default', () {
      expect(addMinutesToTime(null, 0), '08:30:00');
    });
  });

  test('weekday follows JavaScript getDay — Sunday is 0', () {
    expect(weekdayOf('2026-09-27'), 0); // Sunday
    expect(weekdayOf('2026-09-29'), 2); // Tuesday
    expect(weekdayOf('2026-10-03'), 6); // Saturday
  });

  test('HH:MM validation matches the route', () {
    expect(isHhMm('05:00'), isTrue);
    expect(isHhMm('23:59'), isTrue);
    expect(isHhMm('24:00'), isFalse);
    expect(isHhMm('5:00'), isFalse);
    expect(isHhMm(null), isFalse);
  });

  group('punch_at is a UTC instant', () {
    test('a bare DATETIME string is read as UTC, not device time', () {
      final DateTime? t = SqlValue.asUtcInstant('2026-09-29 04:12:00');
      expect(t, DateTime.utc(2026, 9, 29, 4, 12));
      expect(t!.isUtc, isTrue);
    });

    test('shown as school time it is three hours later in EAT', () {
      final DateTime wall = schoolWallTime(DateTime.utc(2026, 9, 29, 4, 12));
      expect(formatClockTime(wall), '07:12');
    });

    test('a punch at 01:30 EAT lands on the school day, not the day before', () {
      // 22:30 UTC on the 28th is 01:30 on the 29th in Kampala.
      final DateTime wall = schoolWallTime(DateTime.utc(2026, 9, 28, 22, 30));
      expect(toLocalDateStr(wall), '2026-09-29');
    });

    test('zero dates and blanks are null', () {
      expect(SqlValue.asUtcInstant('0000-00-00 00:00:00'), isNull);
      expect(SqlValue.asUtcInstant(''), isNull);
      expect(SqlValue.asUtcInstant(null), isNull);
    });
  });

  test('gender matching covers the dirty variants and never blanks', () {
    final ({String sql, List<String> params}) m = genderMatchSql(
      'p.gender',
      'male',
    );
    expect(m.sql, 'LOWER(TRIM(p.gender)) IN (?,?)');
    expect(m.params, <String>['male', 'm']);
    expect(isGenderFilter('female'), isTrue);
    expect(isGenderFilter('Female'), isFalse);
    expect(isGenderFilter(null), isFalse);
  });
}
