/// School-local day and time boundaries, as UTC SQL literals.
///
/// Ported from DRAIS LongTerm:
///
/// * [toUtcBoundary] — `AttendanceFormatter.toUtcBoundary()`
///   (`src/lib/attendance/export/AttendanceFormatter.ts`);
/// * [timeBoundary] — the `timeBoundary` closure in
///   `src/app/api/attendance/history/route.ts`;
/// * [utcDayStart] — `utcBoundary()` in `src/lib/attendance/dashboard-counts.ts`;
/// * [addMinutesToTime] — same file;
/// * [weekdayOf] — `src/lib/attendance/day-overrides.ts`.
///
/// `punch_at` is a real UTC instant, so a school-local day is the window
/// `[localMidnight − offset, +24h)`. `DATE(punch_at)` would put every punch
/// between 00:00 and 02:59 EAT on the previous day — the shortcut the
/// platform's own comments forbid.
library;

String _pad(int n) => n.toString().padLeft(2, '0');

/// `YYYY-MM-DD HH:MM:SS` from a UTC [DateTime].
String formatUtcSql(DateTime utc) {
  final DateTime d = utc.toUtc();
  return '${d.year.toString().padLeft(4, '0')}-${_pad(d.month)}-${_pad(d.day)} '
      '${_pad(d.hour)}:${_pad(d.minute)}:${_pad(d.second)}';
}

DateTime _wall(String localDate, String wallTime) =>
    DateTime.parse('${localDate}T${wallTime}Z');

/// Start (00:00:00) or end (23:59:59) of a school-local day, as UTC SQL.
String toUtcBoundary(
  String localDate, {
  required bool end,
  required int offsetMinutes,
}) => formatUtcSql(
  _wall(
    localDate,
    end ? '23:59:59' : '00:00:00',
  ).subtract(Duration(minutes: offsetMinutes)),
);

/// A school-local date plus `HH:MM`, as UTC SQL — the history route's
/// intra-day window. [endOfMinute] adds 59 seconds, so `11:59` includes the
/// whole minute.
String timeBoundary(
  String localDate,
  String hhmm, {
  required bool endOfMinute,
  required int offsetMinutes,
}) {
  final DateTime start = _wall(
    localDate,
    '00:00:00',
  ).subtract(Duration(minutes: offsetMinutes));
  final List<int> parts = hhmm.split(':').map(int.parse).toList();
  return formatUtcSql(
    start.add(
      Duration(
        seconds: (parts[0] * 60 + parts[1]) * 60 + (endOfMinute ? 59 : 0),
      ),
    ),
  );
}

/// UTC SQL instant for local midnight of [date], plus [plusDays].
String utcDayStart(String date, int offsetMinutes, [int plusDays = 0]) =>
    formatUtcSql(
      _wall(date, '00:00:00')
          .subtract(Duration(minutes: offsetMinutes))
          .add(Duration(days: plusDays)),
    );

/// `HH:MM:SS` plus [mins], wrapped at midnight. A missing time reads as the
/// platform's `08:30:00` default.
String addMinutesToTime(String? hms, int mins) {
  final List<int> p = (hms == null || hms.isEmpty ? '08:30:00' : hms)
      .split(':')
      .map((String x) => int.tryParse(x) ?? 0)
      .toList();
  while (p.length < 3) {
    p.add(0);
  }
  int total = p[0] * 3600 + p[1] * 60 + p[2] + mins * 60;
  total = ((total % 86400) + 86400) % 86400;
  return '${_pad(total ~/ 3600)}:${_pad((total % 3600) ~/ 60)}:${_pad(total % 60)}';
}

/// JavaScript `getDay()` for a calendar date: Sunday is 0.
int weekdayOf(String date) {
  final DateTime d = DateTime.parse(date.substring(0, 10));
  return d.weekday % 7;
}

/// Whether [value] is a valid `HH:MM` — the route's `hhmm` pattern.
bool isHhMm(String? value) =>
    value != null && RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').hasMatch(value);
