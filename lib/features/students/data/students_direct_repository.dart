import 'package:drais/core/database/audit_log.dart';
import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/database/longterm/plan_limits.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/features/students/data/direct/longterm/current_term.dart';
import 'package:drais/features/students/data/direct/longterm/term_resolver.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/features/students/domain/repositories/students_repository.dart';

/// Learners, read and written straight in TiDB — DRAIS LongTerm's student
/// routes, in Dart.
///
/// Each public method reproduces one platform route; the source is cited on
/// each. As everywhere in direct mode, `schoolId` and `userId` come from the
/// validated session, never from a screen.
///
/// ## Not reproduced
///
/// * Fee balances on the Enrolled tab (`getBalancesForStudents`) — Finance is
///   a later module.
/// * Arabic display names (`?lang=ar`) — the app is English-only today.
/// * The admin notification after an admission
///   (`NotificationMiddleware.notifyOnAction`) — it runs through the
///   notification template engine, which is the Notifications module.
/// * Results summary and top subjects on the previous enrolment — Academics.
///
/// All four are listed in `docs/PARITY.md` §4.2.
class StudentsDirectRepository implements StudentsRepository {
  /// Creates the repository.
  StudentsDirectRepository({
    required DraisDatabase database,
    required int schoolId,
    required int userId,
    required bool Function(String code) can,
    required AppLogger logger,
  }) : _db = database,
       _can = can,
       _schoolId = schoolId,
       _userId = userId,
       _audit = AuditLog(database: database, logger: logger),
       _logger = logger.child('StudentsDirect');

  final DraisDatabase _db;
  final int _schoolId;
  final int _userId;

  /// The session's permission test (`AuthUser.can`) — the direct-mode stand-in
  /// for `requirePermission()`, with the same wildcard and super-admin
  /// semantics.
  final bool Function(String code) _can;
  final AuditLog _audit;
  final AppLogger _logger;

  /// The routes' `SAFETY_LIMIT`: all rows up to 10,000, one extra to detect
  /// truncation. Written as a literal — [DraisDatabase.limitClause] clamps at
  /// 500, which would silently cut a real school's roster.
  static const int _safetyLimit = 10000;

  static const String _nameSearch =
      '(LOWER(p.first_name) LIKE ? OR LOWER(p.last_name) LIKE ? '
      'OR s.admission_no LIKE ? '
      "OR LOWER(CONCAT(p.last_name, ' ', p.first_name)) LIKE ? "
      "OR LOWER(CONCAT(p.first_name, ' ', p.last_name)) LIKE ?)";

  // ───────────────────────────────────────────────────────────────────────
  // getCurrentTerm() — src/lib/terms.ts
  // ───────────────────────────────────────────────────────────────────────

  /// The platform's three-step priority (date-matched active, any active,
  /// latest), in one statement: ordering by the two priority flags and then
  /// start date returns the row the three queries would. `today` is a UTC
  /// date, as the platform computes it.
  Future<({int id, String name})?> _currentTerm() =>
      currentTerm(_db, _schoolId);

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/students/enrolled
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<StudentListResult>> enrolled({
    int? termId,
    int? classId,
    String? search,
    String? status,
  }) async {
    try {
      final ({int id, String name})? current = termId == null
          ? await _currentTerm()
          : null;
      final int? resolvedTerm = termId ?? current?.id;

      // s.school_id for isolation — enrollments.school_id may be NULL on
      // rows imported before migration 020 (platform comment).
      final List<String> where = <String>['s.school_id = ?', 's.deleted_at IS NULL'];
      final List<Object?> params = <Object?>[_schoolId];
      if (resolvedTerm != null) {
        where.add('e.term_id = ?');
        params.add(resolvedTerm);
      }
      if (status != null && status.isNotEmpty && status != 'all') {
        where.add('e.status = ?');
        params.add(status);
      }
      if (classId != null) {
        where.add('e.class_id = ?');
        params.add(classId);
      }
      final String? q = search?.trim();
      if (q != null && q.isNotEmpty) {
        where.add(_nameSearch);
        final String like = '%${q.toLowerCase()}%';
        params.addAll(<Object?>[like, like, like, like, like]);
      }

      final List<Row> raw = await _db.query('''
        SELECT
          e.id AS enrollment_id, e.status AS enrollment_status,
          IFNULL(e.enrollment_type, 'new') AS enrollment_type,
          s.id, s.person_id, s.admission_no, s.status AS student_status,
          s.admission_date, s.residency_status,
          p.first_name, p.last_name, p.other_name, p.gender, p.date_of_birth,
          p.photo_url, p.phone, p.email,
          c.name AS class_name, st.name AS stream_name,
          ay.name AS academic_year_name, t.name AS term_name,
          sm.name AS study_mode_name, pr.name AS program_name
        FROM enrollments e
        JOIN students s      ON e.student_id = s.id
        LEFT JOIN people p   ON s.person_id = p.id
        LEFT JOIN classes c         ON e.class_id = c.id
        LEFT JOIN streams st        ON e.stream_id = st.id
        LEFT JOIN academic_years ay ON e.academic_year_id = ay.id
        LEFT JOIN terms t           ON e.term_id = t.id
        LEFT JOIN study_modes sm    ON e.study_mode_id = sm.id
        LEFT JOIN programs pr       ON e.program_id = pr.id
        WHERE ${where.join(' AND ')}
        ORDER BY p.first_name ASC, p.last_name ASC
        LIMIT ${_safetyLimit + 1}
        ''', params);

      final bool truncated = raw.length > _safetyLimit;
      final List<Row> rows = truncated ? raw.sublist(0, _safetyLimit) : raw;

      // Programs per enrolment, batched as the route does.
      final Map<int, List<String>> programs = <int, List<String>>{};
      final List<int> ids = rows
          .map((Row r) => SqlValue.asInt(r['enrollment_id']))
          .whereType<int>()
          .toList();
      if (ids.isNotEmpty) {
        final List<Row> prog = await _db.query(
          'SELECT ep.enrollment_id, p.name FROM enrollment_programs ep '
          'JOIN programs p ON ep.program_id = p.id '
          'WHERE ep.enrollment_id IN (${List<String>.filled(ids.length, '?').join(',')})',
          ids,
        );
        for (final Row r in prog) {
          final int? eid = SqlValue.asInt(r['enrollment_id']);
          final String? name = SqlValue.asString(r['name']);
          if (eid != null && name != null) {
            programs.putIfAbsent(eid, () => <String>[]).add(name);
          }
        }
      }

      return Ok<StudentListResult>(
        StudentListResult(
          rows: rows
              .map(
                (Row r) => _row(
                  r,
                  programs[SqlValue.asInt(r['enrollment_id'])] ?? const <String>[],
                ),
              )
              .toList(growable: false),
          truncated: truncated,
          termId: resolvedTerm,
          termName: current?.name,
        ),
      );
    } on Failure catch (failure) {
      return Err<StudentListResult>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/students/admitted
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<StudentListResult>> admitted({String? search}) async {
    try {
      final ({int id, String name})? current = await _currentTerm();

      final List<String> where = <String>['s.school_id = ?', 's.deleted_at IS NULL'];
      final List<Object?> params = <Object?>[_schoolId];
      if (current != null) {
        where.add('''NOT EXISTS (
          SELECT 1 FROM enrollments e
           WHERE e.student_id = s.id AND e.term_id = ? AND e.status = 'active')''');
        params.add(current.id);
      }
      final String? q = search?.trim();
      if (q != null && q.isNotEmpty) {
        where.add(_nameSearch);
        final String like = '%${q.toLowerCase()}%';
        params.addAll(<Object?>[like, like, like, like, like]);
      }

      final List<Row> raw = await _db.query('''
        SELECT s.id, s.person_id, s.admission_no, s.status AS student_status,
               s.admission_date, s.residency_status,
               p.first_name, p.last_name, p.other_name, p.gender,
               p.date_of_birth, p.photo_url, p.phone, p.email
          FROM students s
          LEFT JOIN people p ON s.person_id = p.id
         WHERE ${where.join(' AND ')}
         ORDER BY p.first_name ASC, p.last_name ASC
         LIMIT ${_safetyLimit + 1}
        ''', params);

      final bool truncated = raw.length > _safetyLimit;
      final List<Row> rows = truncated ? raw.sublist(0, _safetyLimit) : raw;

      return Ok<StudentListResult>(
        StudentListResult(
          rows: rows.map((Row r) => _row(r, const <String>[])).toList(growable: false),
          truncated: truncated,
          termId: current?.id,
          termName: current?.name,
        ),
      );
    } on Failure catch (failure) {
      return Err<StudentListResult>(failure);
    }
  }

  StudentListRow _row(Row r, List<String> programs) {
    String? s(String k) {
      final String? v = SqlValue.asString(r[k]);
      return (v == null || v.isEmpty) ? null : v;
    }

    return StudentListRow(
      id: SqlValue.asInt(r['id']) ?? SqlValue.asInt(r['student_id']) ?? 0,
      personId: SqlValue.asInt(r['person_id']) ?? 0,
      firstName: s('first_name') ?? '',
      lastName: s('last_name') ?? '',
      otherName: s('other_name'),
      admissionNo: s('admission_no'),
      studentStatus: s('student_status'),
      admissionDate: s('admission_date'),
      residencyStatus: s('residency_status'),
      gender: s('gender'),
      dateOfBirth: s('date_of_birth'),
      photoUrl: s('photo_url'),
      phone: s('phone'),
      email: s('email'),
      enrollmentId: SqlValue.asInt(r['enrollment_id']),
      className: s('class_name'),
      streamName: s('stream_name'),
      termName: s('term_name'),
      academicYearName: s('academic_year_name'),
      studyModeName: s('study_mode_name'),
      programName: s('program_name'),
      enrollmentStatus: s('enrollment_status'),
      enrollmentType: s('enrollment_type'),
      programs: programs,
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/students/[id]/profile
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<StudentProfile>> profile(int studentId) async {
    try {
      final Row? core = await _db.queryOne(
        '''
        SELECT s.id AS student_id, s.admission_no, s.status AS student_status,
               s.admission_date, s.residency_status,
               p.id AS person_id, p.first_name, p.last_name, p.other_name,
               p.gender, p.date_of_birth, p.phone, p.email, p.photo_url, p.address
          FROM students s
          JOIN people p ON s.person_id = p.id
         WHERE s.id = ? AND s.school_id = ?
        ''',
        <Object?>[studentId, _schoolId],
      );
      if (core == null) {
        return const Err<StudentProfile>(
          NotFoundFailure(message: 'Student not found'),
        );
      }

      // The route runs these one after another. They are independent, so
      // they are issued together: nine round trips become roughly five on a
      // two-connection pool, with the same rows.
      final List<Object?> sid = <Object?>[studentId];
      final List<List<Row>> r = await Future.wait(<Future<List<Row>>>[
        _db.query(
          'SELECT orphan_status, previous_school, notes '
          'FROM student_additional_info WHERE student_id = ?',
          sid,
        ),
        _db.query('''
          SELECT sp.place_of_birth, sp.place_of_residence,
                 sp.district_id, sp.nationality_id,
                 d.name AS district_name, n.name AS nationality_name
            FROM student_profiles sp
            LEFT JOIN districts d ON sp.district_id = d.id
            LEFT JOIN nationalities n ON sp.nationality_id = n.id
           WHERE sp.student_id = ?''', sid),
        _db.query('''
          SELECT os.label AS orphan_status_label, fs.orphan_status_id,
                 fs.primary_guardian_name, fs.primary_guardian_contact,
                 fs.primary_guardian_occupation,
                 fs.father_name, fs.father_living_status_id,
                 ls_f.label AS father_living_status_label,
                 fs.father_occupation, fs.father_contact, fs.notes
            FROM student_family_status fs
            LEFT JOIN orphan_statuses os ON fs.orphan_status_id = os.id
            LEFT JOIN living_statuses ls_f ON fs.father_living_status_id = ls_f.id
           WHERE fs.student_id = ?''', sid),
        _db.query(
          'SELECT sequence, name, address, occupation, contact FROM student_next_of_kin '
          'WHERE student_id = ? ORDER BY sequence ASC, id ASC',
          sid,
        ),
        _db.query('''
          SELECT pa.name, pa.phone, pa.email, sp.relationship
            FROM student_parents sp
            JOIN parents pa ON sp.parent_id = pa.id
           WHERE sp.student_id = ?''', sid),
        _db.query(
          'SELECT COUNT(*) AS n FROM student_documents '
          'WHERE student_id = ? AND school_id = ?',
          <Object?>[studentId, _schoolId],
        ),
        _db.query('''
          SELECT sc.contact_id, sc.relationship, sc.is_primary, c.occupation,
                 c.alive_status, p.address,
                 p.first_name, p.last_name, p.phone, p.email
            FROM student_contacts sc
            JOIN contacts c ON sc.contact_id = c.id
            LEFT JOIN people p ON c.person_id = p.id
           WHERE sc.student_id = ? AND c.deleted_at IS NULL
           ORDER BY sc.is_primary DESC, p.first_name''', sid),
        _db.query('''
          SELECT COUNT(*) AS total,
                 SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active_count
            FROM student_fingerprints
           WHERE student_id = ? AND school_id = ?''', <Object?>[studentId, _schoolId]),
        _enrollmentHistory(studentId),
      ]);

      final Row? additional = r[0].firstOrNull;
      final Row? extended = r[1].firstOrNull;
      final Row? family = r[2].firstOrNull;
      final Row? fp = r[7].firstOrNull;
      String? v(Row? row, String k) {
        final String? x = SqlValue.asString(row?[k]);
        return (x == null || x.isEmpty) ? null : x;
      }

      final List<EnrollmentRecord> enrollments = await _withPrograms(r[8]);

      return Ok<StudentProfile>(
        StudentProfile(
          row: _row(core, const <String>[]),
          enrollments: enrollments,
          parents: r[4]
              .map(
                (Row p) => StudentRelation(
                  name: v(p, 'name') ?? 'Parent',
                  relationship: v(p, 'relationship'),
                  phone: v(p, 'phone'),
                  email: v(p, 'email'),
                ),
              )
              .toList(growable: false),
          contacts: r[6]
              .map(
                (Row c) => StudentRelation(
                  contactId: SqlValue.asInt(c['contact_id']),
                  firstName: v(c, 'first_name'),
                  lastName: v(c, 'last_name'),
                  address: v(c, 'address'),
                  aliveStatus: v(c, 'alive_status'),
                  name: <String?>[v(c, 'first_name'), v(c, 'last_name')]
                      .whereType<String>()
                      .join(' '),
                  relationship: v(c, 'relationship'),
                  phone: v(c, 'phone'),
                  email: v(c, 'email'),
                  occupation: v(c, 'occupation'),
                  isPrimary: SqlValue.asBool(c['is_primary']),
                ),
              )
              .toList(growable: false),
          nextOfKin: r[3]
              .map(
                (Row k) => StudentRelation(
                  name: v(k, 'name') ?? 'Next of kin',
                  phone: v(k, 'contact'),
                  occupation: v(k, 'occupation'),
                ),
              )
              .toList(growable: false),
          previousSchool: v(additional, 'previous_school'),
          notes: v(additional, 'notes'),
          orphanStatus:
              v(family, 'orphan_status_label') ?? v(additional, 'orphan_status'),
          placeOfBirth: v(extended, 'place_of_birth'),
          placeOfResidence: v(extended, 'place_of_residence'),
          district: v(extended, 'district_name'),
          nationality: v(extended, 'nationality_name'),
          guardianName: v(family, 'primary_guardian_name'),
          guardianContact: v(family, 'primary_guardian_contact'),
          fatherName: v(family, 'father_name'),
          fatherContact: v(family, 'father_contact'),
          fatherStatus: v(family, 'father_living_status_label'),
          documentCount: SqlValue.asInt(r[5].firstOrNull?['n']) ?? 0,
          fingerprintsTotal: SqlValue.asInt(fp?['total']) ?? 0,
          fingerprintsActive: SqlValue.asInt(fp?['active_count']) ?? 0,
          address: v(core, 'address'),
          nextOfKinEntries: r[3]
              .map(
                (Row k) => NextOfKinEntry(
                  sequence: SqlValue.asInt(k['sequence']),
                  name: v(k, 'name') ?? '',
                  address: v(k, 'address'),
                  occupation: v(k, 'occupation'),
                  contact: v(k, 'contact'),
                ),
              )
              .toList(growable: false),
          blocks: ProfileBlocks(
            orphanStatus: v(additional, 'orphan_status'),
            previousSchool: v(additional, 'previous_school'),
            notes: v(additional, 'notes'),
            placeOfBirth: v(extended, 'place_of_birth'),
            placeOfResidence: v(extended, 'place_of_residence'),
            districtId: SqlValue.asInt(extended?['district_id']),
            nationalityId: SqlValue.asInt(extended?['nationality_id']),
            orphanStatusId: SqlValue.asInt(family?['orphan_status_id']),
            guardianName: v(family, 'primary_guardian_name'),
            guardianContact: v(family, 'primary_guardian_contact'),
            guardianOccupation: v(family, 'primary_guardian_occupation'),
            fatherName: v(family, 'father_name'),
            fatherLivingStatusId: SqlValue.asInt(family?['father_living_status_id']),
            fatherOccupation: v(family, 'father_occupation'),
            fatherContact: v(family, 'father_contact'),
            familyNotes: v(family, 'notes'),
          ),
        ),
      );
    } on Failure catch (failure) {
      return Err<StudentProfile>(failure);
    }
  }

  static const String _enrollmentSelect = '''
    SELECT e.id AS enrollment_id, e.class_id, c.name AS class_name,
           c.class_level, st.name AS stream_name,
           e.academic_year_id, ay.name AS academic_year_name,
           e.term_id, t.name AS term_name,
           e.study_mode_id, sm.name AS study_mode_name,
           e.curriculum_id, cur.name AS curriculum_name,
           e.program_id, pr.name AS program_name,
           e.enrollment_type, e.status, e.enrollment_date, e.end_date, e.end_reason
      FROM enrollments e
      LEFT JOIN classes c          ON e.class_id = c.id
      LEFT JOIN streams st         ON e.stream_id = st.id
      LEFT JOIN academic_years ay  ON e.academic_year_id = ay.id
      LEFT JOIN terms t            ON e.term_id = t.id
      LEFT JOIN study_modes sm     ON e.study_mode_id = sm.id
      LEFT JOIN curriculums cur    ON e.curriculum_id = cur.id
      LEFT JOIN programs pr        ON e.program_id = pr.id''';

  Future<List<Row>> _enrollmentHistory(int studentId) => _db.query(
    '$_enrollmentSelect '
    'WHERE e.student_id = ? AND e.school_id = ? '
    'ORDER BY e.enrollment_date DESC, e.id DESC',
    <Object?>[studentId, _schoolId],
  );

  Future<List<EnrollmentRecord>> _withPrograms(List<Row> rows) async {
    final List<int> ids = rows
        .map((Row r) => SqlValue.asInt(r['enrollment_id']))
        .whereType<int>()
        .toList();
    final Map<int, List<String>> programs = <int, List<String>>{};
    if (ids.isNotEmpty) {
      final List<Row> ep = await _db.query(
        'SELECT ep.enrollment_id, pr.name FROM enrollment_programs ep '
        'JOIN programs pr ON ep.program_id = pr.id '
        'WHERE ep.enrollment_id IN (${List<String>.filled(ids.length, '?').join(',')})',
        ids,
      );
      for (final Row r in ep) {
        final int? eid = SqlValue.asInt(r['enrollment_id']);
        final String? name = SqlValue.asString(r['name']);
        if (eid != null && name != null) {
          programs.putIfAbsent(eid, () => <String>[]).add(name);
        }
      }
    }
    return rows.map((Row r) {
      String? v(String k) {
        final String? x = SqlValue.asString(r[k]);
        return (x == null || x.isEmpty) ? null : x;
      }

      final int id = SqlValue.asInt(r['enrollment_id']) ?? 0;
      return EnrollmentRecord(
        enrollmentId: id,
        classId: SqlValue.asInt(r['class_id']),
        className: v('class_name'),
        classLevel: SqlValue.asInt(r['class_level']),
        streamName: v('stream_name'),
        academicYearId: SqlValue.asInt(r['academic_year_id']),
        academicYearName: v('academic_year_name'),
        termId: SqlValue.asInt(r['term_id']),
        termName: v('term_name'),
        studyModeId: SqlValue.asInt(r['study_mode_id']),
        studyModeName: v('study_mode_name'),
        curriculumId: SqlValue.asInt(r['curriculum_id']),
        curriculumName: v('curriculum_name'),
        programId: SqlValue.asInt(r['program_id']),
        programName: v('program_name'),
        enrollmentType: v('enrollment_type'),
        status: v('status'),
        enrollmentDate: v('enrollment_date'),
        endDate: v('end_date'),
        endReason: v('end_reason'),
        programs: programs[id] ?? const <String>[],
      );
    }).toList(growable: false);
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/students/[id]/previous-enrollment
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<EnrollmentRecord?>> previousEnrollment(int studentId) async {
    try {
      final List<Row> rows = await _db.query(
        '$_enrollmentSelect '
        'WHERE e.student_id = ? AND e.school_id = ? '
        'ORDER BY ay.start_date DESC, t.start_date DESC, e.id DESC LIMIT 1',
        <Object?>[studentId, _schoolId],
      );
      if (rows.isEmpty) return const Ok<EnrollmentRecord?>(null);
      final List<EnrollmentRecord> records = await _withPrograms(rows);
      return Ok<EnrollmentRecord?>(records.first);
    } on Failure catch (failure) {
      return Err<EnrollmentRecord?>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // The enrol form's lookups
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<EnrollmentOptions>> enrollmentOptions() async {
    try {
      final List<Object?> school = <Object?>[_schoolId];
      final List<List<Row>> r = await Future.wait(<Future<List<Row>>>[
        // resolveTermContext() — src/lib/academic/term-resolver.ts
        _db.query('''
          SELECT t.id, t.name, t.academic_year_id, t.start_date, t.end_date,
                 ay.name AS academic_year_name
            FROM terms t
            LEFT JOIN academic_years ay ON t.academic_year_id = ay.id
           WHERE t.school_id = ? AND t.deleted_at IS NULL
           ORDER BY t.start_date ASC, t.id ASC''', school),
        // /api/classes
        _db.query(
          'SELECT c.id, c.name, c.class_level FROM classes c '
          'WHERE c.school_id = ? AND c.deleted_at IS NULL '
          'ORDER BY c.class_level, c.name',
          school,
        ),
        // /api/streams (all; the form filters by class, as the web refetch does)
        _db.query(
          'SELECT id, name, class_id FROM streams WHERE school_id = ? ORDER BY name ASC',
          school,
        ),
        // /api/study-modes — school modes, else the system defaults
        _db.query(
          'SELECT id, name, is_default FROM study_modes '
          'WHERE school_id = ? AND is_active = 1 ORDER BY is_default DESC, name ASC',
          school,
        ),
        _db.query(
          'SELECT id, name, is_default FROM study_modes '
          'WHERE school_id IS NULL AND is_active = 1 ORDER BY is_default DESC, name ASC',
        ),
        // /api/curriculums
        _db.query(
          'SELECT id, code, name FROM curriculums '
          'WHERE school_id = ? AND deleted_at IS NULL ORDER BY name',
          school,
        ),
        // /api/programs
        _db.query(
          "SELECT id, COALESCE(NULLIF(display_name, ''), name) AS display_name, is_default "
          'FROM programs WHERE school_id = ? AND is_active = 1 '
          'ORDER BY is_default DESC, is_active DESC, display_name ASC',
          school,
        ),
        _db.query(
          'SELECT utc_offset_minutes FROM attendance_time_policy '
          'WHERE school_id = ? LIMIT 1',
          school,
        ).catchError((Object _) => <Row>[]),
      ]);

      final int offset =
          SqlValue.asInt(r[7].firstOrNull?['utc_offset_minutes']) ??
          defaultOffsetMinutes;
      final String today = schoolLocalToday(offsetMinutes: offset);

      final List<TermChoice> terms = r[0].map((Row t) {
        final String? start = SqlValue.asString(t['start_date']);
        final String? end = SqlValue.asString(t['end_date']);
        return TermChoice(
          id: SqlValue.asInt(t['id']) ?? 0,
          name: SqlValue.asString(t['name']) ?? '',
          academicYearId: SqlValue.asInt(t['academic_year_id']),
          academicYearName: SqlValue.asString(t['academic_year_name']),
          startDate: start,
          endDate: end,
          derivedStatus: deriveTermStatus(start, end, today),
        );
      }).toList(growable: false);

      Choice choice(Row row, {String label = 'name'}) => Choice(
        id: SqlValue.asInt(row['id']) ?? 0,
        label: SqlValue.asString(row[label]) ?? '',
        isDefault: SqlValue.asBool(row['is_default']),
        parentId: SqlValue.asInt(row['class_id']),
        level: SqlValue.asInt(row['class_level']),
      );

      final List<Row> modes = r[3].isNotEmpty ? r[3] : r[4];

      return Ok<EnrollmentOptions>(
        EnrollmentOptions(
          terms: terms,
          currentTerm: effectiveTerm(terms),
          classes: r[1].map(choice).toList(growable: false),
          streams: r[2].map(choice).toList(growable: false),
          studyModes: modes.map(choice).toList(growable: false),
          curriculums: r[5].map(choice).toList(growable: false),
          programs: r[6]
              .map((Row row) => choice(row, label: 'display_name'))
              .toList(growable: false),
        ),
      );
    } on Failure catch (failure) {
      return Err<EnrollmentOptions>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/students — src/app/api/students/route.ts
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<AdmissionResult>> admit(AdmissionRequest request) async {
    try {
      // Capacity is checked before anything else, as the route does.
      final String? overCapacity = await checkCapacity(_db, _schoolId, 'learners');
      if (overCapacity != null) {
        return Err<AdmissionResult>(
          AuthorizationFailure(code: ApiErrorCode.forbidden, message: overCapacity),
        );
      }

      final String first = request.firstName.trim();
      final String last = request.lastName.trim();
      if (first.isEmpty || last.isEmpty) {
        return const Err<AdmissionResult>(
          ValidationFailure(
            message: 'Missing required fields: first_name, last_name',
          ),
        );
      }

      final String? gate = await enforcePlanLimit(_db, _schoolId, 'learners');
      if (gate != null) {
        return Err<AdmissionResult>(
          AuthorizationFailure(code: ApiErrorCode.forbidden, message: gate),
        );
      }

      String? orNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

      // The route saves first/last name, email and phone. other_name, gender
      // and date_of_birth are sent by the web form and dropped by the route;
      // they are dropped here too, so both surfaces create identical rows.
      // See docs/PARITY.md §4.2.
      final ({int personId, int studentId}) ids = await _db.transaction(
        (DbTransaction tx) async {
          final int? personId = await tx.insert(
            'INSERT INTO people (school_id, first_name, last_name, email, phone) '
            'VALUES (?, ?, ?, ?, ?)',
            <Object?>[_schoolId, first, last, orNull(request.email), orNull(request.phone)],
          );
          final int? studentId = await tx.insert(
            'INSERT INTO students (school_id, person_id, status, admission_date) '
            "VALUES (?, ?, 'active', NOW())",
            <Object?>[_schoolId, personId],
          );
          if (personId == null || studentId == null) {
            throw const ServerFailure(message: 'Failed to create student');
          }
          return (personId: personId, studentId: studentId);
        },
      );

      await _audit.write(
        schoolId: _schoolId,
        userId: _userId,
        action: 'ENROLLED_STUDENT',
        entityType: 'student',
        entityId: ids.studentId,
        details: <String, Object?>{
          'first_name': first,
          'last_name': last,
          'class_id': null,
        },
      );

      _logger.info(
        'Admitted a learner.',
        context: <String, Object?>{'studentId': ids.studentId},
      );
      return Ok<AdmissionResult>(
        AdmissionResult(studentId: ids.studentId, personId: ids.personId),
      );
    } on Failure catch (failure) {
      return Err<AdmissionResult>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/enrollments — src/app/api/enrollments/route.ts
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<String>> enroll(EnrollmentRequest req) async {
    try {
      // The route checks six references one after another and reports the
      // first missing one. They are fetched together here and reported in
      // the same order, so the outcome is identical.
      final List<Row?> found = await Future.wait(<Future<Row?>>[
        _db.queryOne(
          'SELECT s.id, p.first_name, p.last_name FROM students s '
          'JOIN people p ON s.person_id = p.id '
          'WHERE s.id = ? AND s.school_id = ? AND s.deleted_at IS NULL LIMIT 1',
          <Object?>[req.studentId, _schoolId],
        ),
        _db.queryOne(
          'SELECT id, name FROM classes WHERE id = ? AND school_id = ? LIMIT 1',
          <Object?>[req.classId, _schoolId],
        ),
        _db.queryOne(
          'SELECT id FROM academic_years WHERE id = ? AND school_id = ? LIMIT 1',
          <Object?>[req.academicYearId, _schoolId],
        ),
        _db.queryOne(
          'SELECT id FROM terms WHERE id = ? AND school_id = ? LIMIT 1',
          <Object?>[req.termId, _schoolId],
        ),
        _db.queryOne(
          'SELECT id, name FROM curriculums WHERE id = ? LIMIT 1',
          <Object?>[req.curriculumId],
        ),
        _db.queryOne(
          'SELECT id, name FROM programs WHERE id = ? AND school_id = ? AND is_active = 1 LIMIT 1',
          <Object?>[req.programId, _schoolId],
        ),
      ]);

      const List<String> missing = <String>[
        'Student not found or does not belong to this school',
        'Class not found',
        'Academic year not found',
        'Term not found',
        'Curriculum not found',
        'Program not found or inactive',
      ];
      for (int i = 0; i < found.length; i++) {
        if (found[i] == null) {
          return Err<String>(NotFoundFailure(message: missing[i]));
        }
      }

      final Row student = found[0]!;
      final String studentName =
          '${SqlValue.asString(student['first_name']) ?? ''} '
          '${SqlValue.asString(student['last_name']) ?? ''}';
      final String className = SqlValue.asString(found[1]!['name']) ?? '';
      final String curriculumName = SqlValue.asString(found[4]!['name']) ?? '';
      final String programName = SqlValue.asString(found[5]!['name']) ?? '';

      final ({int enrollmentId, Row? previous}) done = await _db.transaction(
        (DbTransaction tx) async {
          final Row? prev = await tx.queryOne(
            'SELECT id, class_id FROM enrollments '
            "WHERE student_id = ? AND school_id = ? AND status = 'active' LIMIT 1",
            <Object?>[req.studentId, _schoolId],
          );

          // The web form always sends close_previous: true.
          await tx.execute(
            "UPDATE enrollments SET status = 'completed', end_date = CURDATE(), "
            "end_reason = 'promoted', updated_at = NOW() "
            "WHERE student_id = ? AND school_id = ? AND status = 'active'",
            <Object?>[req.studentId, _schoolId],
          );

          final int? enrollmentId = await tx.insert(
            '''
            INSERT INTO enrollments
              (school_id, student_id, class_id, stream_id, academic_year_id, term_id,
               study_mode_id, curriculum_id, program_id, enrollment_type, status, enrollment_date, enrolled_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', CURDATE(), NOW())
            ''',
            <Object?>[
              _schoolId,
              req.studentId,
              req.classId,
              req.streamId,
              req.academicYearId,
              req.termId,
              req.studyModeId,
              req.curriculumId,
              req.programId,
              req.decision.enrollmentType,
            ],
          );
          if (enrollmentId == null) {
            throw const ServerFailure(message: 'Enrollment failed');
          }

          await tx.execute(
            'INSERT IGNORE INTO enrollment_programs (enrollment_id, program_id) VALUES (?, ?)',
            <Object?>[enrollmentId, req.programId],
          );
          return (enrollmentId: enrollmentId, previous: prev);
        },
      );

      final bool moved = done.previous != null;
      final String message = moved
          ? '$studentName moved to $className'
          : '$studentName enrolled in $className';

      // Post-commit, non-blocking on the platform; awaited here but never
      // allowed to fail the enrolment.
      await _audit.write(
        schoolId: _schoolId,
        userId: _userId,
        action: moved ? 'REASSIGNED_CLASS' : 'ENROLLED_STUDENT',
        entityType: 'enrollment',
        entityId: done.enrollmentId,
        details: <String, Object?>{
          'student_id': req.studentId,
          'class_id': req.classId,
          'class_name': className,
          'stream_id': req.streamId,
          'academic_year_id': req.academicYearId,
          'term_id': req.termId,
          'study_mode_id': req.studyModeId,
          'curriculum_id': req.curriculumId,
          'curriculum_name': curriculumName,
          'program_id': req.programId,
          'program_name': programName,
          'program_ids': <int>[req.programId],
          'enrollment_type': req.decision.enrollmentType,
          'previous_enrollment_id': SqlValue.asInt(done.previous?['id']),
          'previous_class_id': SqlValue.asInt(done.previous?['class_id']),
        },
      );
      try {
        await _db.execute(
          '''
          INSERT INTO notifications (school_id, actor_user_id, action, entity_type, entity_id, title, message, priority, channel, created_at)
          VALUES (?, ?, ?, 'enrollment', ?, ?, ?, 'normal', 'in_app', NOW())
          ''',
          <Object?>[
            _schoolId,
            _userId,
            moved ? 'CLASS_CHANGED' : 'STUDENT_ENROLLED',
            done.enrollmentId,
            moved ? 'Student Class Changed' : 'Student Enrolled',
            message,
          ],
        );
      } on Failure catch (failure) {
        _logger.warn(
          'Enrolment notification failed.',
          context: <String, Object?>{'reason': failure.technicalDetail},
        );
      }

      return Ok<String>(message);
    } on Failure catch (failure) {
      return Err<String>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Permission gate — requirePermission() in src/lib/rbac.ts
  // ───────────────────────────────────────────────────────────────────────

  Failure? _forbidden(String code) => _can(code)
      ? null
      : AuthorizationFailure(
          code: ApiErrorCode.forbidden,
          message: "Forbidden: missing permission '$code'",
        );

  // ───────────────────────────────────────────────────────────────────────
  // PUT /api/students/edit — src/app/api/students/edit/route.ts
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<void>> update(int studentId, StudentEdit edit) async {
    try {
      final Map<String, String> fields = edit.fields;

      final Map<String, ({Object? old, Object? now})>? changed = await _db
          .transaction((DbTransaction tx) async {
            final Row? current = await tx.queryOne(
              '''
              SELECT s.id, s.person_id, s.status AS student_status,
                     p.first_name, p.last_name, p.other_name, p.gender,
                     p.date_of_birth, p.phone, p.email, p.address, p.photo_url
                FROM students s JOIN people p ON s.person_id = p.id
               WHERE s.id = ? AND s.school_id = ? AND s.deleted_at IS NULL
              ''',
              <Object?>[studentId, _schoolId],
            );
            if (current == null) return null;

            final Map<String, ({Object? old, Object? now})> diff =
                <String, ({Object? old, Object? now})>{};
            if (fields.isNotEmpty) {
              // Column names come from StudentEdit's fixed key set, never
              // from input — the route's whitelist, preserved.
              final List<String> sets = <String>[];
              final List<Object?> params = <Object?>[];
              fields.forEach((String col, String value) {
                sets.add('$col = ?');
                params.add(value);
                if (value != SqlValue.asString(current[col])) {
                  diff[col] = (old: current[col], now: value);
                }
              });
              sets.add('updated_at = NOW()');
              params.add(current['person_id']);
              await tx.execute(
                'UPDATE people SET ${sets.join(', ')} WHERE id = ?',
                params,
              );
            }
            return diff;
          });

      if (changed == null) {
        return const Err<void>(
          NotFoundFailure(message: 'Student not found or access restricted'),
        );
      }

      if (changed.isNotEmpty) {
        final List<String> keys = changed.keys.toList();
        await _audit.write(
          schoolId: _schoolId,
          userId: _userId,
          action: 'STUDENT_UPDATED',
          entityType: 'student',
          entityId: studentId,
          details: <String, Object?>{
            'changed_fields': keys,
            'old_values': <String, Object?>{
              for (final String k in keys)
                k: changed[k]!.old == null ? null : '${changed[k]!.old}',
            },
            'new_values': <String, Object?>{
              for (final String k in keys) k: changed[k]!.now,
            },
          },
        );
      }
      return const Ok<void>(null);
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/students/bulk/status — src/app/api/students/bulk/status/route.ts
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<String>> setStatus(
    int studentId,
    StudentStatus status, {
    String? reason,
  }) async {
    try {
      final String? why = reason?.trim();
      if (status == StudentStatus.left && (why == null || why.isEmpty)) {
        return const Err<String>(
          ValidationFailure(message: 'Reason required for "left" status'),
        );
      }

      final Row? owned = await _db.queryOne(
        'SELECT COUNT(*) AS cnt FROM students '
        'WHERE school_id = ? AND deleted_at IS NULL AND id IN (?)',
        <Object?>[_schoolId, studentId],
      );
      if ((SqlValue.asInt(owned?['cnt']) ?? 0) != 1) {
        return const Err<String>(
          AuthorizationFailure(
            code: ApiErrorCode.forbidden,
            message: 'Some students do not belong to your school',
          ),
        );
      }

      final String extra = switch (status) {
        StudentStatus.left => ', left_at = NOW(), left_reason = ?',
        StudentStatus.graduated => ', left_at = NOW()',
        _ => '',
      };
      await _db.execute(
        'UPDATE students SET status = ?, updated_at = NOW()$extra '
        'WHERE school_id = ? AND id IN (?)',
        <Object?>[
          status.wireValue,
          if (status == StudentStatus.left) why,
          _schoolId,
          studentId,
        ],
      );
      return Ok<String>('Updated 1 student(s) to "${status.wireValue}"');
    } on Failure catch (failure) {
      return Err<String>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // PATCH /api/students/[id]/residency
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<void>> setResidency(int studentId, String residency) async {
    try {
      final Failure? denied = _forbidden('academics.residency.manage');
      if (denied != null) return Err<void>(denied);
      if (residency != 'day' && residency != 'boarding') {
        return const Err<void>(
          ValidationFailure(
            message: 'Invalid residency_status. Must be one of: day, boarding',
          ),
        );
      }

      final Row? existing = await _db.queryOne(
        'SELECT id, residency_status FROM students '
        'WHERE id = ? AND school_id = ? AND deleted_at IS NULL',
        <Object?>[studentId, _schoolId],
      );
      if (existing == null) {
        return const Err<void>(
          NotFoundFailure(message: 'Student not found or access denied'),
        );
      }
      final String? previous = SqlValue.asString(existing['residency_status']);

      await _db.execute(
        '''
        UPDATE students
           SET residency_status = ?, residency_status_updated_at = NOW(), residency_status_updated_by = ?
         WHERE id = ? AND school_id = ?
        ''',
        <Object?>[residency, _userId, studentId, _schoolId],
      );

      if (previous != residency) {
        await _audit.write(
          schoolId: _schoolId,
          userId: _userId,
          action: 'RESIDENCY_STATUS_CHANGED',
          entityType: 'student',
          entityId: studentId,
          details: <String, Object?>{'old': previous, 'new': residency},
        );
      }
      return const Ok<void>(null);
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // DELETE /api/students/delete — archiveEntity() in src/lib/trash/service.ts
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<void>> archive(int studentId, {String? reason}) async {
    try {
      final String? why = (reason == null || reason.trim().isEmpty)
          ? null
          : reason.trim();

      // fetchRow(): a snapshot for the audit log.
      final Row? before = await _db.queryOne(
        'SELECT * FROM `students` WHERE id = ? AND school_id = ? LIMIT 1',
        <Object?>[studentId, _schoolId],
      );
      if (before == null) {
        return const Err<void>(NotFoundFailure(message: 'Learner not found'));
      }
      if (before['deleted_at'] != null) {
        return const Err<void>(
          ConflictFailure(message: 'Learner is already archived'),
        );
      }

      final int affected = await _db.execute(
        '''
        UPDATE `students`
           SET deleted_at = NOW(), deleted_by = ?, delete_reason = ?
         WHERE id = ? AND school_id = ? AND deleted_at IS NULL
        ''',
        <Object?>[_userId, why, studentId, _schoolId],
      );
      if (affected == 0) {
        return const Err<void>(NotFoundFailure(message: 'Learner not found'));
      }

      final Row? after = await _db.queryOne(
        'SELECT * FROM `students` WHERE id = ? AND school_id = ? LIMIT 1',
        <Object?>[studentId, _schoolId],
      );
      await _audit.write(
        schoolId: _schoolId,
        userId: _userId,
        action: 'ARCHIVED_STUDENT',
        entityType: 'student',
        entityId: studentId,
        details: <String, Object?>{
          'reason': why,
          'before': _jsonSafe(before),
          'after': _jsonSafe(after),
        },
      );

      // Biometric identity safety (suspendEnrollmentsForRole): an archived
      // learner must stop being recognised on devices. Suspended, not
      // revoked, so a restore can reactivate. Best-effort, as on the
      // platform — never blocks the archive.
      await _suspendBiometrics(studentId);
      return const Ok<void>(null);
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }

  Future<void> _suspendBiometrics(int studentId) async {
    try {
      final List<Row> rows = await _db.query(
        '''
        SELECT id, person_id, pin_value, origin_device_sn
          FROM biometric_enrollments
         WHERE school_id = ? AND role_type = ? AND role_ref_id = ?
           AND status IN ('active','pending_capture')
        ''',
        <Object?>[_schoolId, 'student', studentId],
      );
      for (final Row r in rows) {
        await _db.execute(
          '''
          UPDATE biometric_enrollments
             SET status = 'suspended', revoked_reason = ?, updated_by = ?, updated_at = CURRENT_TIMESTAMP
           WHERE id = ? AND school_id = ?
          ''',
          <Object?>['person_archived', _userId, r['id'], _schoolId],
        );
        try {
          await _db.execute(
            '''
            INSERT INTO biometric_mapping_history
              (school_id, enrollment_id, device_sn, pin_value, action,
               old_role_type, old_role_ref_id, old_person_id,
               new_role_type, new_role_ref_id, new_person_id,
               reason, actor_user_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            <Object?>[
              _schoolId,
              r['id'],
              r['origin_device_sn'],
              r['pin_value'],
              'suspend_person_archived',
              'student',
              studentId,
              r['person_id'],
              null,
              null,
              null,
              'person_archived',
              _userId,
            ],
          );
        } on Failure {
          // recordMappingHistory() swallows its own failures.
        }
      }
    } on Failure catch (failure) {
      _logger.warn(
        'Biometric suspend on archive failed (non-fatal).',
        context: <String, Object?>{'reason': failure.technicalDetail},
      );
    }
  }

  /// Row values made JSON-encodable for the audit snapshot.
  static Map<String, Object?>? _jsonSafe(Row? row) => row?.map(
    (String k, Object? v) => MapEntry<String, Object?>(
      k,
      v == null || v is num || v is bool || v is String ? v : '$v',
    ),
  );

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/students/list?view=trash
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<List<TrashedStudent>>> trash({String? search}) async {
    try {
      final List<Object?> params = <Object?>[_schoolId];
      String where = 's.school_id = ? AND s.deleted_at IS NOT NULL';
      final String? q = search?.trim();
      if (q != null && q.isNotEmpty) {
        where +=
            ' AND (LOWER(p.first_name) LIKE LOWER(?) '
            'OR LOWER(p.last_name) LIKE LOWER(?) OR s.admission_no LIKE ?)';
        final String like = '%$q%';
        params.addAll(<Object?>[like, like, like]);
      }
      final List<Row> rows = await _db.query('''
        SELECT DISTINCT s.id, s.admission_no, s.deleted_at, s.delete_reason,
               p.first_name, p.last_name,
               (SELECT COUNT(*) FROM enrollments WHERE student_id = s.id AND school_id = s.school_id) AS enrollment_count,
               (SELECT COUNT(*) FROM results WHERE student_id = s.id AND school_id = s.school_id) AS result_count
          FROM students s
          JOIN people p ON s.person_id = p.id
         WHERE $where
         ORDER BY s.deleted_at DESC
         LIMIT ${_safetyLimit + 1}
        ''', params);

      return Ok<List<TrashedStudent>>(
        rows
            .take(_safetyLimit)
            .map(
              (Row r) => TrashedStudent(
                id: SqlValue.asInt(r['id']) ?? 0,
                name:
                    '${SqlValue.asString(r['first_name']) ?? ''} '
                            '${SqlValue.asString(r['last_name']) ?? ''}'
                        .trim(),
                admissionNo: SqlValue.asString(r['admission_no']),
                deletedAt: SqlValue.asString(r['deleted_at']),
                deleteReason: SqlValue.asString(r['delete_reason']),
                enrollmentCount: SqlValue.asInt(r['enrollment_count']) ?? 0,
                resultCount: SqlValue.asInt(r['result_count']) ?? 0,
              ),
            )
            .toList(growable: false),
      );
    } on Failure catch (failure) {
      return Err<List<TrashedStudent>>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/students/restore — src/app/api/students/restore/route.ts
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<int>> restore(List<int> studentIds) async {
    try {
      final List<int> ids = studentIds.where((int n) => n > 0).toList();
      if (ids.isEmpty) {
        return const Err<int>(ValidationFailure(message: 'No valid student IDs'));
      }
      final String marks = List<String>.filled(ids.length, '?').join(',');

      // Charge capacity only for rows that will actually come back.
      final Row? pending = await _db.queryOne(
        'SELECT COUNT(*) AS n FROM students '
        'WHERE school_id = ? AND deleted_at IS NOT NULL AND id IN ($marks)',
        <Object?>[_schoolId, ...ids],
      );
      final int willRestore = SqlValue.asInt(pending?['n']) ?? 0;
      if (willRestore > 0) {
        final String? over = await checkCapacity(
          _db,
          _schoolId,
          'learners',
          requested: willRestore,
        );
        if (over != null) {
          return Err<int>(
            AuthorizationFailure(code: ApiErrorCode.forbidden, message: over),
          );
        }
      }

      // The route restores with a direct UPDATE — it does not call
      // restoreEntity(), so biometric enrolments suspended on archive are
      // NOT reactivated. Reproduced; see docs/PARITY.md §4.2.
      final int restored = await _db.execute(
        '''
        UPDATE students
           SET deleted_at = NULL, restored_at = NOW(), restored_by = ?
         WHERE school_id = ? AND deleted_at IS NOT NULL AND id IN ($marks)
        ''',
        <Object?>[_userId, _schoolId, ...ids],
      );
      await _audit.write(
        schoolId: _schoolId,
        userId: _userId,
        action: 'RESTORED_STUDENT',
        entityType: 'student',
        entityId: ids.length == 1 ? ids.first : null,
        details: <String, Object?>{'ids': ids, 'restored': restored},
      );
      return Ok<int>(restored);
    } on Failure catch (failure) {
      return Err<int>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/students/[id]/next-of-kin
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<void>> saveNextOfKin(
    int studentId,
    List<NextOfKinEntry> items,
  ) async {
    try {
      final Failure? denied = _forbidden('learners.profile.update');
      if (denied != null) return Err<void>(denied);
      if (!await _ownsStudent(studentId)) {
        return const Err<void>(NotFoundFailure(message: 'Student not found'));
      }

      await _db.transaction((DbTransaction tx) async {
        await tx.execute(
          'DELETE FROM student_next_of_kin WHERE student_id = ?',
          <Object?>[studentId],
        );
        int seq = 1;
        for (final NextOfKinEntry it in items) {
          final String name = it.name.trim();
          if (name.isEmpty) continue;
          // `it.sequence ?? seq++` — the counter only advances when used.
          final int sequence = it.sequence ?? seq++;
          await tx.execute(
            'INSERT INTO student_next_of_kin '
            '(student_id, sequence, name, address, occupation, contact) '
            'VALUES (?, ?, ?, ?, ?, ?)',
            <Object?>[
              studentId,
              sequence,
              name,
              it.address,
              it.occupation,
              it.contact,
            ],
          );
        }
      });
      return const Ok<void>(null);
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }

  Future<bool> _ownsStudent(int studentId) async =>
      await _db.queryOne(
        'SELECT id FROM students WHERE id = ? AND school_id = ? AND deleted_at IS NULL',
        <Object?>[studentId, _schoolId],
      ) !=
      null;

  // ───────────────────────────────────────────────────────────────────────
  // PUT /api/students/[id]/profile
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<void>> saveProfileBlocks(
    int studentId,
    ProfileBlocks b,
  ) async {
    try {
      final Failure? denied = _forbidden('learners.profile.update');
      if (denied != null) return Err<void>(denied);

      // The route verifies ownership without the deleted_at filter.
      final Row? owned = await _db.queryOne(
        'SELECT id FROM students WHERE id = ? AND school_id = ?',
        <Object?>[studentId, _schoolId],
      );
      if (owned == null) {
        return const Err<void>(NotFoundFailure(message: 'Student not found'));
      }

      // Not one transaction on the platform: each block is its own
      // statement. Reproduced.
      await _db.execute(
        '''
        INSERT INTO student_additional_info (student_id, orphan_status, previous_school, notes)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          orphan_status = VALUES(orphan_status),
          previous_school = VALUES(previous_school),
          notes = VALUES(notes)
        ''',
        <Object?>[studentId, b.orphanStatus, b.previousSchool, b.notes],
      );

      // student_profiles has no UNIQUE on student_id; emulated upsert.
      final bool hasProfile =
          await _db.queryOne(
            'SELECT student_id FROM student_profiles WHERE student_id = ?',
            <Object?>[studentId],
          ) !=
          null;
      final List<Object?> ext = <Object?>[
        b.placeOfBirth,
        b.placeOfResidence,
        b.districtId,
        b.nationalityId,
      ];
      if (hasProfile) {
        await _db.execute(
          '''
          UPDATE student_profiles
             SET place_of_birth = ?, place_of_residence = ?, district_id = ?, nationality_id = ?, updated_at = NOW()
           WHERE student_id = ?
          ''',
          <Object?>[...ext, studentId],
        );
      } else {
        await _db.execute(
          'INSERT INTO student_profiles '
          '(student_id, place_of_birth, place_of_residence, district_id, nationality_id) '
          'VALUES (?, ?, ?, ?, ?)',
          <Object?>[studentId, ...ext],
        );
      }

      final bool hasFamily =
          await _db.queryOne(
            'SELECT student_id FROM student_family_status WHERE student_id = ?',
            <Object?>[studentId],
          ) !=
          null;
      final List<Object?> fam = <Object?>[
        b.orphanStatusId,
        b.guardianName,
        b.guardianContact,
        b.guardianOccupation,
        b.fatherName,
        b.fatherLivingStatusId,
        b.fatherOccupation,
        b.fatherContact,
        b.familyNotes,
      ];
      if (hasFamily) {
        await _db.execute(
          '''
          UPDATE student_family_status SET
            orphan_status_id = ?, primary_guardian_name = ?, primary_guardian_contact = ?,
            primary_guardian_occupation = ?, father_name = ?, father_living_status_id = ?,
            father_occupation = ?, father_contact = ?, notes = ?, updated_at = NOW()
          WHERE student_id = ?
          ''',
          <Object?>[...fam, studentId],
        );
      } else {
        await _db.execute(
          '''
          INSERT INTO student_family_status
            (student_id, orphan_status_id, primary_guardian_name, primary_guardian_contact,
             primary_guardian_occupation, father_name, father_living_status_id,
             father_occupation, father_contact, notes, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
          ''',
          <Object?>[studentId, ...fam],
        );
      }
      return const Ok<void>(null);
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }
}
