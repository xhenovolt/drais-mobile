/// Term resolution.
///
/// **Ported from `resolveTermContext()` in
/// `src/lib/academic/term-resolver.ts`** (DRAIS LongTerm). Date truth wins,
/// and there is **no** fallback to a stale manually-active term (the
/// platform's "Term I forever" bug).
///
/// Dates are compared as calendar days in the school's timezone. Stored term
/// dates are `DATE` values, so the platform's `+offset` shift never moves
/// them off their own day, and a string comparison of `YYYY-MM-DD` is
/// equivalent.
library;

import 'package:drais/features/students/domain/entities/students.dart';

/// `upcoming` | `current` | `completed` | `unknown`.
String deriveTermStatus(String? start, String? end, String today) {
  final String? s = _day(start);
  final String? e = _day(end);
  if (s == null || e == null) return 'unknown';
  if (today.compareTo(s) < 0) return 'upcoming';
  if (today.compareTo(e) > 0) return 'completed';
  return 'current';
}

String? _day(String? v) {
  if (v == null || v.length < 10) return null;
  return v.substring(0, 10);
}

/// The first term (in start-date order) whose dates cover today, or null.
TermChoice? effectiveTerm(List<TermChoice> termsOldestFirst) {
  for (final TermChoice t in termsOldestFirst) {
    if (t.derivedStatus == 'current') return t;
  }
  return null;
}
