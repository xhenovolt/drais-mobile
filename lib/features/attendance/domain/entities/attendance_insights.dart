/// Day counts and per-person profiles, as LongTerm computes them.
library;

import 'package:drais/features/attendance/domain/entities/attendance_history.dart';

/// Present / late / absent for one role — `RoleCounts` in
/// `src/lib/attendance/dashboard-counts.ts`.
class RoleCounts {
  /// Creates role counts.
  const RoleCounts({
    this.total = 0,
    this.present = 0,
    this.late = 0,
    this.absent = 0,
  });

  /// Active roster size.
  final int total;

  /// Distinct matched people with at least one punch that day.
  final int present;

  /// Of [present], those whose first punch was after the role's cutoff.
  final int late;

  /// `total − present`, floored at zero.
  final int absent;
}

/// The dashboard's attendance block — `DashboardAttendanceCounts`.
class DashboardAttendanceCounts {
  /// Creates dashboard counts.
  const DashboardAttendanceCounts({
    required this.date,
    this.students = const RoleCounts(),
    this.staff = const RoleCounts(),
  });

  /// School-local `YYYY-MM-DD` the counts are for.
  final String date;

  /// Learners.
  final RoleCounts students;

  /// Staff.
  final RoleCounts staff;

  /// The dashboard's `attendancePercentage`: learners present over roster,
  /// rounded — `/api/dashboard/overview`.
  int get attendancePercentage => students.total > 0
      ? (students.present / students.total * 100).round()
      : 0;
}

/// What the home screen shows about today.
class TodayAttendance {
  /// Creates today's snapshot.
  const TodayAttendance({required this.counts, this.recent});

  /// Present / late / absent.
  final DashboardAttendanceCounts counts;

  /// The latest punches, when they loaded. A failure here leaves the counts
  /// standing rather than blanking the card.
  final AttendanceHistoryPage? recent;
}

/// One day's verdict for one person — `PersonDay`.
class PersonDay {
  /// Creates a person-day.
  const PersonDay({required this.date, required this.status});

  /// School-local `YYYY-MM-DD`.
  final String date;

  /// `attendance_records.status`.
  final String status;
}

/// A behavioural classification — `Behaviour` in `person-intelligence.ts`.
enum Behaviour {
  /// Present, little lateness.
  reliable('reliable'),

  /// Late 15–35% of days.
  occasionallyLate('occasionally_late'),

  /// Late 35%+ of days.
  chronicallyLate('chronically_late'),

  /// Absent 20%+ of days.
  frequentlyAbsent('frequently_absent'),

  /// Absence rising against their own history.
  declining('declining'),

  /// Absence falling against their own history.
  improving('improving'),

  /// Tracked but never showed up — roster noise, not behaviour.
  neverPresent('never_present'),

  /// Fewer than four graded days.
  insufficientData('insufficient_data');

  const Behaviour(this.wireValue);

  /// The platform's value.
  final String wireValue;
}

/// A person's attendance character — `PersonProfile`.
class PersonProfile {
  /// Creates a profile.
  const PersonProfile({
    required this.trackedDays,
    required this.presentRate,
    required this.lateRate,
    required this.absentRate,
    required this.currentAbsentStreak,
    required this.longestAbsentStreak,
    required this.recentAbsentRate,
    required this.priorAbsentRate,
    required this.behaviour,
    required this.label,
    required this.note,
    required this.watch,
    required this.rosterReview,
  });

  /// Graded days in the window.
  final int trackedDays;

  /// Present, late or half day — 0..1.
  final double presentRate;

  /// Late — 0..1.
  final double lateRate;

  /// Absent — 0..1.
  final double absentRate;

  /// Trailing run of absences.
  final int currentAbsentStreak;

  /// Longest run of absences.
  final int longestAbsentStreak;

  /// Absence rate over the second half of the window.
  final double recentAbsentRate;

  /// Absence rate over the first half.
  final double priorAbsentRate;

  /// Classification.
  final Behaviour behaviour;

  /// Human label.
  final String label;

  /// Admin-facing sentence.
  final String note;

  /// On the behavioural watch-list.
  final bool watch;

  /// Likely former or unenrolled — a roster question.
  final bool rosterReview;
}

/// `GET /api/attendance/person-profiles?person_id=` — one person's profile
/// plus the verdict series it was computed from.
class PersonAttendance {
  /// Creates a person's attendance.
  const PersonAttendance({
    required this.personId,
    required this.role,
    required this.days,
    required this.profile,
    required this.series,
  });

  /// `people.id`.
  final int personId;

  /// `student` or `staff`.
  final String role;

  /// Window length.
  final int days;

  /// The profile.
  final PersonProfile profile;

  /// Oldest first, as the route returns it.
  final List<PersonDay> series;
}
