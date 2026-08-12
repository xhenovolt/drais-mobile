/// Timezone-safe `YYYY-MM-DD` handling.
///
/// ## The bug this exists to prevent
///
/// `DateTime.toIso8601String().substring(0, 10)` renders in whatever the
/// `DateTime` holds, and `toUtc()` first is worse: for any timezone **east of
/// UTC** — and EAT is +03:00 — reading a UTC date rolls the local day
/// backwards. A teacher opening the register at 09:00 in Kampala would be
/// shown yesterday's attendance, and nothing about the screen would say so.
///
/// This is the Dart twin of `src/lib/datetime/local-date.ts` in DRAIS
/// LongTerm, whose header calls the UTC version "the footgun this replaces"
/// (ADR-0004). The two must stay in step: a date computed here is compared
/// against `attendance_records.attendance_date` rows written by that one.
///
/// **Never format an attendance date any other way.**
library;

/// EAT (Africa/Kampala) — the DRAIS default school timezone, in minutes.
const int defaultOffsetMinutes = 180;

/// Formats a [DateTime] as `YYYY-MM-DD` from its **local** calendar
/// components.
///
/// Use wherever the device clock is the operator's on-site time — which on a
/// phone in the school is always. The local components *are* the school-local
/// date, so no conversion is wanted or safe.
String toLocalDateStr([DateTime? date]) {
  final DateTime d = date ?? DateTime.now();
  final String month = d.month.toString().padLeft(2, '0');
  final String day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$month-$day';
}

/// School-local "today" as `YYYY-MM-DD` for a timezone [offsetMinutes].
///
/// Use when the clock is **not** the school's — a server in UTC, or a phone
/// carried outside the school's timezone. Shifts the instant by the offset
/// first, then reads the now-local date.
///
/// A teacher travelling does not change what day it is at their school, which
/// is the whole reason this takes an explicit offset rather than trusting the
/// device.
String schoolLocalToday({
  int offsetMinutes = defaultOffsetMinutes,
  DateTime? now,
}) {
  final DateTime instant = (now ?? DateTime.now()).toUtc();
  final DateTime shifted = instant.add(Duration(minutes: offsetMinutes));
  return toLocalDateStr(DateTime(shifted.year, shifted.month, shifted.day));
}

/// Parses a `YYYY-MM-DD` string into a local [DateTime] at midnight.
///
/// Returns null for anything unparseable. Deliberately does **not** accept a
/// full timestamp: this type is for calendar dates, and silently truncating a
/// timestamp would hide exactly the timezone confusion the library prevents.
DateTime? parseLocalDate(String? value) {
  if (value == null || value.length != 10) return null;

  final List<String> parts = value.split('-');
  if (parts.length != 3) return null;

  final int? year = int.tryParse(parts[0]);
  final int? month = int.tryParse(parts[1]);
  final int? day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  final DateTime parsed = DateTime(year, month, day);
  // Reject dates that rolled — 2026-02-31 parses to 3 March otherwise.
  if (parsed.month != month || parsed.day != day) return null;
  return parsed;
}

/// Shifts a `YYYY-MM-DD` string by [days], staying in calendar space.
String shiftLocalDate(String date, int days) {
  final DateTime? parsed = parseLocalDate(date);
  if (parsed == null) return date;
  return toLocalDateStr(parsed.add(Duration(days: days)));
}

/// Whether [date] is the school-local today.
bool isToday(String date, {int offsetMinutes = defaultOffsetMinutes}) =>
    date == toLocalDateStr();

/// A short, human label for a date — "Today", "Yesterday", or `Mon 10 Aug`.
///
/// Relative labels only reach back one day. Beyond that "3 days ago" makes a
/// reader do arithmetic to work out which register they are looking at, and
/// attendance is a record where the specific day matters.
String describeLocalDate(String date) {
  final DateTime? parsed = parseLocalDate(date);
  if (parsed == null) return date;

  final String today = toLocalDateStr();
  if (date == today) return 'Today';
  if (date == shiftLocalDate(today, -1)) return 'Yesterday';

  const List<String> weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final String weekday = weekdays[parsed.weekday - 1];
  final String month = months[parsed.month - 1];
  return '$weekday ${parsed.day} $month';
}

/// Formats a punch time as `HH:MM`, from local components.
String formatClockTime(DateTime? at) {
  if (at == null) return '—';
  final String hour = at.hour.toString().padLeft(2, '0');
  final String minute = at.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
