/// A learner, as a list needs them.
///
/// Deliberately thin. The full record — guardians, fees, results, documents —
/// belongs on a detail screen and behind its own permission checks; a roster
/// row needs only enough to find the right person and see where they are.
class StudentSummary {
  /// Creates a student summary.
  const StudentSummary({
    required this.id,
    required this.personId,
    required this.firstName,
    required this.lastName,
    this.admissionNo,
    this.className,
    this.status = 'active',
    this.todayStatus,
  });

  /// `students.id`.
  final int id;

  /// `students.person_id` — the key attendance is recorded against.
  ///
  /// Attendance rows carry `person_id`, not `student_id`, because staff and
  /// learners share one identity space. Joining on the wrong one silently
  /// returns nothing.
  final int personId;

  /// Given name, from `people`.
  final String firstName;

  /// Family name, from `people`.
  final String lastName;

  /// `students.admission_no`. Null for learners admitted before numbering, or
  /// still being processed — 2 of the 851 in production.
  final String? admissionNo;

  /// Class name from the learner's **current active enrollment**.
  ///
  /// Not from `students.class_id`, which is unpopulated for every row in
  /// production. Class membership lives in `enrollments`, scoped by term.
  final String? className;

  /// `students.status`.
  final String status;

  /// Today's attendance verdict, when the caller asked for it.
  final String? todayStatus;

  /// Name as it should be shown.
  String get displayName {
    final String composed = '$firstName $lastName'.trim();
    return composed.isEmpty ? 'Unnamed learner' : composed;
  }

  /// Initials for an avatar.
  String get initials {
    final String a = firstName.trim().isNotEmpty ? firstName.trim()[0] : '';
    final String b = lastName.trim().isNotEmpty ? lastName.trim()[0] : '';
    final String combined = '$a$b'.trim();
    return combined.isEmpty ? '?' : combined.toUpperCase();
  }

  /// Whether this learner is currently enrolled.
  bool get isActive => status.toLowerCase() == 'active';

  @override
  String toString() => 'StudentSummary($id, $displayName, $className)';
}

/// A learner's full record, as a phone needs it.
///
/// Everything here answers a question someone asks *while standing in front of
/// the learner or their guardian*: who are they, which class, have they been
/// coming in, and who do I call. Fees, results and documents are deliberately
/// absent — each has its own permission and its own screen.
class StudentDetail {
  /// Creates a detail record.
  const StudentDetail({
    required this.summary,
    this.gender,
    this.dateOfBirth,
    this.phone,
    this.email,
    this.address,
    this.photoUrl,
    this.attendance = const <StudentAttendanceDay>[],
  });

  /// The roster-level fields.
  final StudentSummary summary;

  /// `people.gender`.
  final String? gender;

  /// `people.date_of_birth`.
  final DateTime? dateOfBirth;

  /// `people.phone`.
  final String? phone;

  /// `people.email`.
  final String? email;

  /// `people.address`.
  final String? address;

  /// `people.photo_url`.
  final String? photoUrl;

  /// Recent attendance, newest first.
  final List<StudentAttendanceDay> attendance;

  /// Age in whole years, when a date of birth is on file.
  int? get age {
    final DateTime? dob = dateOfBirth;
    if (dob == null) return null;

    final DateTime now = DateTime.now();
    int years = now.year - dob.year;
    // Not yet had this year's birthday.
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years < 0 || years > 120 ? null : years;
  }

  /// Days present or late, over the loaded window.
  int get daysAttended =>
      attendance.where((StudentAttendanceDay d) => d.isAttendance).length;

  /// Days marked absent, over the loaded window.
  int get daysAbsent =>
      attendance.where((StudentAttendanceDay d) => d.status == 'absent').length;

  /// Attendance rate over the window, ignoring weekends and holidays.
  ///
  /// Null when there is nothing to divide by — showing "0%" for a learner with
  /// no records would read as a problem rather than as an absence of data.
  double? get attendanceRate {
    final int schoolDays = attendance
        .where((StudentAttendanceDay d) => d.countsTowardRate)
        .length;
    if (schoolDays == 0) return null;
    return daysAttended / schoolDays;
  }
}

/// One day of a learner's attendance.
class StudentAttendanceDay {
  /// Creates a day.
  const StudentAttendanceDay({
    required this.date,
    required this.status,
    this.lateMinutes,
    this.firstInAt,
  });

  /// The school-local date.
  final DateTime date;

  /// The engine's verdict.
  final String status;

  /// How late, in minutes.
  final int? lateMinutes;

  /// First punch of the day.
  final DateTime? firstInAt;

  /// Whether the learner was there in some form.
  bool get isAttendance =>
      status == 'present' || status == 'late' || status == 'half_day';

  /// Whether the day belongs in an attendance-rate denominator.
  ///
  /// Weekends and holidays do not — counting them would drag every learner's
  /// rate down by the same amount and make the number meaningless.
  bool get countsTowardRate => status != 'weekend' && status != 'holiday';
}
