import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/datetime/local_date.dart';

/// The bug these prevent is the one LongTerm's own header calls "the footgun":
/// formatting an attendance date through UTC. East of UTC — and EAT is +03:00 —
/// that rolls the local day backwards, so a teacher opening the register in
/// the morning is shown yesterday and nothing on screen says so.
void main() {
  group('toLocalDateStr', () {
    test('formats from local components, never UTC', () {
      // 01:30 local on the 11th. Read as UTC in EAT this becomes the 10th.
      final DateTime earlyMorning = DateTime(2026, 8, 11, 1, 30);

      expect(toLocalDateStr(earlyMorning), '2026-08-11');
    });

    test('pads month and day', () {
      expect(toLocalDateStr(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('handles the last instant of a day', () {
      expect(toLocalDateStr(DateTime(2026, 8, 11, 23, 59, 59)), '2026-08-11');
    });
  });

  group('schoolLocalToday', () {
    test('shifts by the offset before reading the date', () {
      // 22:00 UTC on the 10th is 01:00 on the 11th in EAT — the school's day
      // has already rolled over even though UTC says otherwise.
      final DateTime utcEvening = DateTime.utc(2026, 8, 10, 22);

      expect(schoolLocalToday(now: utcEvening), '2026-08-11');
    });

    test('a zero offset is plain UTC', () {
      final DateTime utcEvening = DateTime.utc(2026, 8, 10, 22);

      expect(schoolLocalToday(offsetMinutes: 0, now: utcEvening), '2026-08-10');
    });
  });

  group('parseLocalDate', () {
    test('parses a valid date', () {
      expect(parseLocalDate('2026-08-11'), DateTime(2026, 8, 11));
    });

    test('rejects malformed input', () {
      expect(parseLocalDate(null), isNull);
      expect(parseLocalDate(''), isNull);
      expect(parseLocalDate('2026-8-1'), isNull);
      expect(parseLocalDate('11/08/2026'), isNull);
      expect(parseLocalDate('2026-08-11T09:00:00Z'), isNull);
    });

    test('rejects dates that would roll', () {
      // DateTime(2026, 2, 31) silently becomes 3 March; that must not pass.
      expect(parseLocalDate('2026-02-31'), isNull);
      expect(parseLocalDate('2026-13-01'), isNull);
    });
  });

  group('shiftLocalDate', () {
    test('steps across a month boundary', () {
      expect(shiftLocalDate('2026-08-31', 1), '2026-09-01');
      expect(shiftLocalDate('2026-09-01', -1), '2026-08-31');
    });

    test('steps across a year boundary', () {
      expect(shiftLocalDate('2026-12-31', 1), '2027-01-01');
    });

    test('handles a leap day', () {
      expect(shiftLocalDate('2028-02-28', 1), '2028-02-29');
    });

    test('returns the input unchanged when it is unparseable', () {
      expect(shiftLocalDate('rubbish', 1), 'rubbish');
    });
  });

  group('describeLocalDate', () {
    test('labels today and yesterday relatively', () {
      final String today = toLocalDateStr();

      expect(describeLocalDate(today), 'Today');
      expect(describeLocalDate(shiftLocalDate(today, -1)), 'Yesterday');
    });

    test('names the day beyond that, rather than counting back', () {
      // Relative to today, never a hardcoded date — a fixed date drifts into
      // "Yesterday" as the calendar moves and the test starts failing for a
      // reason that has nothing to do with the code.
      final String older = shiftLocalDate(toLocalDateStr(), -5);
      final DateTime parsed = parseLocalDate(older)!;

      final String described = describeLocalDate(older);
      expect(described, isNot(contains('ago')));
      expect(described, isNot('Today'));
      expect(described, isNot('Yesterday'));
      // `Wed 6 Aug` — weekday, day, short month.
      expect(
        described,
        matches(RegExp(r'^[A-Z][a-z]{2} \d{1,2} [A-Z][a-z]{2}$')),
      );
      expect(described, contains('${parsed.day}'));
    });
  });

  group('formatClockTime', () {
    test('pads to HH:MM', () {
      expect(formatClockTime(DateTime(2026, 8, 11, 7, 5)), '07:05');
      expect(formatClockTime(DateTime(2026, 8, 11, 19, 42)), '19:42');
    });

    test('shows a dash for a missing time', () {
      expect(formatClockTime(null), '—');
    });
  });
}
