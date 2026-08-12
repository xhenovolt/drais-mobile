import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/domain/student_summary.dart';

/// Reads the learner roster straight from TiDB, for direct mode.
///
/// ## Two traps this navigates
///
/// **Class membership is not on `students`.** `students.class_id` is
/// unpopulated for every row in production — 0 of 851. The real link is
/// `enrollments`, which carries the class, term and academic year.
///
/// **Enrollments duplicate.** A learner has one row per term they have been
/// enrolled in, so joining naively returns each learner several times. The
/// query below filters to the active, undeleted enrollment and groups, which
/// is what keeps a roster of 851 from rendering as 877 rows with repeats.
///
/// As everywhere in direct mode, `schoolId` comes from the validated session,
/// never from the UI.
class StudentsDirectRepository {
  /// Creates the repository.
  StudentsDirectRepository({
    required DraisDatabase database,
    required int schoolId,
  }) : _db = database,
       _schoolId = schoolId;

  final DraisDatabase _db;
  final int _schoolId;

  /// Lists learners, optionally filtered by name, admission number or class.
  Future<Result<List<StudentSummary>>> list({
    String? search,
    String? className,
    String? attendanceDate,
    int limit = 60,
    int offset = 0,
  }) async {
    try {
      final StringBuffer where = StringBuffer(
        's.school_id = ? AND s.deleted_at IS NULL',
      );
      final List<Object?> params = <Object?>[_schoolId];

      final String? term = search?.trim();
      if (term != null && term.isNotEmpty) {
        where.write(
          ' AND (LOWER(p.first_name) LIKE ? OR LOWER(p.last_name) LIKE ?'
          ' OR LOWER(COALESCE(s.admission_no, '
          ')) LIKE ?)',
        );
        final String pattern = '%${term.toLowerCase()}%';
        params.addAll(<Object?>[pattern, pattern, pattern]);
      }

      if (className != null && className.isNotEmpty) {
        where.write(' AND c.name = ?');
        params.add(className);
      }

      // Today's verdict is optional: joining it for a plain roster costs a
      // scan of attendance_records for no benefit.
      final bool withAttendance =
          attendanceDate != null && attendanceDate.isNotEmpty;
      final String attendanceSelect = withAttendance
          ? ', ar.status AS today_status'
          : ', NULL AS today_status';
      final String attendanceJoin = withAttendance
          ? '''
            LEFT JOIN attendance_records ar
                   ON ar.person_id = s.person_id
                  AND ar.role_type = 'student'
                  AND ar.attendance_date = ?
            '''
          : '';

      final List<Object?> ordered = <Object?>[
        if (withAttendance) attendanceDate,
        ...params,
      ];

      final List<Row> rows = await _db.query('''
        SELECT s.id, s.person_id, s.admission_no, s.status,
               p.first_name, p.last_name,
               c.name AS class_name
               $attendanceSelect
          FROM students s
          JOIN people p ON p.id = s.person_id
          LEFT JOIN enrollments e
                 ON e.student_id = s.id
                AND e.deleted_at IS NULL
                AND e.status = 'active'
          LEFT JOIN classes c ON c.id = e.class_id
          $attendanceJoin
         WHERE $where
         GROUP BY s.id, s.person_id, s.admission_no, s.status,
                  p.first_name, p.last_name, c.name
                  ${withAttendance ? ', ar.status' : ''}
         ORDER BY p.first_name, p.last_name
         ${DraisDatabase.limitClause(limit: limit, offset: offset)}
        ''', ordered);

      return Ok<List<StudentSummary>>(
        rows
            .map(
              (Row row) => StudentSummary(
                id: SqlValue.asInt(row['id']) ?? 0,
                personId: SqlValue.asInt(row['person_id']) ?? 0,
                firstName: SqlValue.asString(row['first_name']) ?? '',
                lastName: SqlValue.asString(row['last_name']) ?? '',
                admissionNo: SqlValue.asString(row['admission_no']),
                className: SqlValue.asString(row['class_name']),
                status: SqlValue.asString(row['status']) ?? 'active',
                todayStatus: SqlValue.asString(row['today_status']),
              ),
            )
            .toList(growable: false),
      );
    } on Failure catch (failure) {
      return Err<List<StudentSummary>>(failure);
    }
  }

  /// The classes that currently have learners, for the filter row.
  Future<Result<List<String>>> classes() async {
    try {
      final List<Row> rows = await _db.query(
        '''
        SELECT DISTINCT c.name
          FROM classes c
         WHERE c.school_id = ? AND c.deleted_at IS NULL
         ORDER BY c.name
        ''',
        <Object?>[_schoolId],
      );
      return Ok<List<String>>(
        rows
            .map((Row r) => SqlValue.asString(r['name']))
            .whereType<String>()
            .toList(growable: false),
      );
    } on Failure catch (failure) {
      return Err<List<String>>(failure);
    }
  }

  /// One learner, with recent attendance.
  ///
  /// [days] bounds the history — a phone showing every record since admission
  /// would load thousands of rows to render a scroll nobody reads.
  Future<Result<StudentDetail>> detail(int studentId, {int days = 30}) async {
    try {
      final Row? row = await _db.queryOne(
        '''
        SELECT s.id, s.person_id, s.admission_no, s.status,
               p.first_name, p.last_name, p.gender, p.date_of_birth,
               p.phone, p.email, p.address, p.photo_url,
               c.name AS class_name
          FROM students s
          JOIN people p ON p.id = s.person_id
          LEFT JOIN enrollments e
                 ON e.student_id = s.id
                AND e.deleted_at IS NULL
                AND e.status = 'active'
          LEFT JOIN classes c ON c.id = e.class_id
         WHERE s.id = ? AND s.school_id = ? AND s.deleted_at IS NULL
         GROUP BY s.id, s.person_id, s.admission_no, s.status,
                  p.first_name, p.last_name, p.gender, p.date_of_birth,
                  p.phone, p.email, p.address, p.photo_url, c.name
         LIMIT 1
        ''',
        // school_id is in the WHERE clause, not just the join: without it a
        // guessed student id from another school would resolve.
        <Object?>[studentId, _schoolId],
      );

      if (row == null) {
        return const Err<StudentDetail>(
          NotFoundFailure(message: 'That learner could not be found.'),
        );
      }

      final int personId = SqlValue.asInt(row['person_id']) ?? 0;
      final List<Row> history = await _db.query(
        '''
        SELECT ar.attendance_date, ar.status, ar.late_minutes, ar.first_in_at
          FROM attendance_records ar
         WHERE ar.person_id = ?
           AND ar.role_type = 'student'
           AND ar.school_id = ?
           AND ar.attendance_date >= DATE_SUB(CURDATE(), INTERVAL $days DAY)
         ORDER BY ar.attendance_date DESC
         ${DraisDatabase.limitClause(limit: days + 10)}
        ''',
        <Object?>[personId, _schoolId],
      );

      return Ok<StudentDetail>(
        StudentDetail(
          summary: StudentSummary(
            id: SqlValue.asInt(row['id']) ?? 0,
            personId: personId,
            firstName: SqlValue.asString(row['first_name']) ?? '',
            lastName: SqlValue.asString(row['last_name']) ?? '',
            admissionNo: SqlValue.asString(row['admission_no']),
            className: SqlValue.asString(row['class_name']),
            status: SqlValue.asString(row['status']) ?? 'active',
          ),
          gender: SqlValue.asString(row['gender']),
          dateOfBirth: SqlValue.asDate(row['date_of_birth']),
          phone: SqlValue.asString(row['phone']),
          email: SqlValue.asString(row['email']),
          address: SqlValue.asString(row['address']),
          photoUrl: SqlValue.asString(row['photo_url']),
          attendance: history
              .map(
                (Row r) => StudentAttendanceDay(
                  date: SqlValue.asDate(r['attendance_date']) ?? DateTime.now(),
                  status: SqlValue.asString(r['status']) ?? 'absent',
                  lateMinutes: SqlValue.asInt(r['late_minutes']),
                  firstInAt: SqlValue.asDate(r['first_in_at']),
                ),
              )
              .toList(growable: false),
        ),
      );
    } on Failure catch (failure) {
      return Err<StudentDetail>(failure);
    }
  }

  /// Total enrolled learners.
  Future<Result<int>> count() async {
    try {
      final Row? row = await _db.queryOne(
        'SELECT COUNT(*) AS n FROM students '
        'WHERE school_id = ? AND deleted_at IS NULL',
        <Object?>[_schoolId],
      );
      return Ok<int>(SqlValue.asInt(row?['n']) ?? 0);
    } on Failure catch (failure) {
      return Err<int>(failure);
    }
  }
}
