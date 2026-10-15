import 'package:drais/core/database/audit_log.dart';
import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/features/students/data/direct/longterm/current_term.dart';
import 'package:drais/features/students/data/direct/longterm/duplicates.dart';
import 'package:drais/features/students/domain/entities/student_admin.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/features/students/domain/repositories/student_admin_repository.dart';

/// Contacts, duplicates and bulk enrolment, straight in TiDB — DRAIS
/// LongTerm's routes, in Dart.
///
/// ## One deliberate correction
///
/// `PUT` and `DELETE /api/students/contacts/[id]` look the contact up **by id
/// alone**, with no `school_id` check, so on the platform any school can
/// edit or delete another school's contact by guessing an id. That is a
/// tenant-isolation hole, and it is not reproduced: [updateContact] and
/// [removeContact] add `AND school_id = ?`. Everything else matches the
/// route. See `docs/PARITY.md` §4.2.
class StudentAdminDirectRepository implements StudentAdminRepository {
  /// Creates the repository.
  StudentAdminDirectRepository({
    required DraisDatabase database,
    required int schoolId,
    required int userId,
    required AppLogger logger,
  }) : _db = database,
       _schoolId = schoolId,
       _userId = userId,
       _audit = AuditLog(database: database, logger: logger),
       _logger = logger.child('StudentAdminDirect');

  final DraisDatabase _db;
  final int _schoolId;
  final int _userId;
  final AuditLog _audit;
  final AppLogger _logger;

  static String _marks(int n) => List<String>.filled(n, '?').join(',');

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/students/contacts
  // ───────────────────────────────────────────────────────────────────────

  static const String _contactsFrom = '''
    FROM student_contacts sc
    JOIN contacts c ON sc.contact_id = c.id AND c.deleted_at IS NULL AND c.school_id = ?
    JOIN people cp ON c.person_id = cp.id
    JOIN students s ON sc.student_id = s.id AND s.deleted_at IS NULL
    JOIN people sp ON s.person_id = sp.id
    LEFT JOIN (
      SELECT student_id, MAX(id) AS latest_enrollment_id
        FROM enrollments
       WHERE status = 'active'
       GROUP BY student_id
    ) latest_e ON latest_e.student_id = s.id
    LEFT JOIN enrollments e ON e.id = latest_e.latest_enrollment_id
    LEFT JOIN classes cl ON cl.id = e.class_id
    WHERE s.school_id = ?''';

  @override
  Future<Result<ContactPage>> contacts({
    int? studentId,
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final int p = page < 1 ? 1 : page;
      final int l = limit.clamp(1, 200);
      final List<Object?> params = <Object?>[_schoolId, _schoolId];
      final StringBuffer filters = StringBuffer();
      if (studentId != null) {
        filters.write(' AND sc.student_id = ?');
        params.add(studentId);
      }
      final String? q = search?.trim();
      if (q != null && q.isNotEmpty) {
        filters.write(
          ' AND (sp.first_name LIKE ? OR sp.last_name LIKE ? '
          'OR cp.first_name LIKE ? OR cp.last_name LIKE ? OR sc.relationship LIKE ?)',
        );
        final String like = '%$q%';
        params.addAll(<Object?>[like, like, like, like, like]);
      }

      final List<Object> r = await Future.wait(<Future<Object>>[
        _db
            .queryOne(
              "SELECT COUNT(DISTINCT CONCAT(sc.student_id, ':', sc.contact_id)) AS total "
              '$_contactsFrom$filters',
              params,
            )
            .then((Row? row) => SqlValue.asInt(row?['total']) ?? 0),
        _db.query('''
          SELECT DISTINCT
            sc.student_id, sc.contact_id, sc.relationship, sc.is_primary,
            c.contact_type, c.occupation, c.alive_status,
            cp.first_name AS contact_first_name, cp.last_name AS contact_last_name,
            cp.phone AS contact_phone, cp.email AS contact_email, cp.address AS contact_address,
            sp.first_name AS student_first_name, sp.last_name AS student_last_name,
            s.admission_no, cl.name AS class_name
          $_contactsFrom$filters
          ORDER BY COALESCE(sp.last_name, '') ASC, COALESCE(sp.first_name, '') ASC, sc.is_primary DESC
          ${DraisDatabase.limitClause(limit: l, offset: (p - 1) * l)}
          ''', params),
      ]);

      String? v(Row row, String k) {
        final String? x = SqlValue.asString(row[k]);
        return (x == null || x.isEmpty) ? null : x;
      }

      return Ok<ContactPage>(
        ContactPage(
          total: r[0] as int,
          page: p,
          limit: l,
          rows: (r[1] as List<Row>)
              .map(
                (Row row) => ContactRow(
                  studentId: SqlValue.asInt(row['student_id']) ?? 0,
                  contactId: SqlValue.asInt(row['contact_id']) ?? 0,
                  relationship: v(row, 'relationship'),
                  isPrimary: SqlValue.asBool(row['is_primary']),
                  contactType: v(row, 'contact_type'),
                  occupation: v(row, 'occupation'),
                  aliveStatus: v(row, 'alive_status'),
                  firstName: v(row, 'contact_first_name'),
                  lastName: v(row, 'contact_last_name'),
                  phone: v(row, 'contact_phone'),
                  email: v(row, 'contact_email'),
                  address: v(row, 'contact_address'),
                  studentFirstName: v(row, 'student_first_name'),
                  studentLastName: v(row, 'student_last_name'),
                  admissionNo: v(row, 'admission_no'),
                  className: v(row, 'class_name'),
                ),
              )
              .toList(growable: false),
        ),
      );
    } on Failure catch (failure) {
      return Err<ContactPage>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/students/contacts (JSON quick-add)
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<String>> addContact(int studentId, ContactInput c) async {
    try {
      if (c.phone.trim().isEmpty) {
        return const Err<String>(
          ValidationFailure(message: 'Student ID and phone number are required'),
        );
      }

      final String? outcome = await _db.transaction((DbTransaction tx) async {
        final Row? student = await tx.queryOne(
          'SELECT id FROM students WHERE id = ? AND school_id = ? AND deleted_at IS NULL',
          <Object?>[studentId, _schoolId],
        );
        if (student == null) {
          throw const NotFoundFailure(
            message: 'Student not found or does not belong to your school',
          );
        }

        // findExistingContact(): same phone (punctuation ignored) or email.
        final String phone = normalizePhone(c.phone);
        final String email = normalizeEmail(c.email);
        final Row? existing = await tx.queryOne(
          '''
          SELECT c.id,
                 EXISTS(SELECT 1 FROM student_contacts sc2 WHERE sc2.contact_id = c.id AND sc2.student_id = ?) AS linked_to_student
            FROM contacts c
            JOIN people cp ON cp.id = c.person_id
           WHERE c.school_id = ? AND c.deleted_at IS NULL AND cp.deleted_at IS NULL
             AND (REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(cp.phone, ' ', ''), '.', ''), '-', ''), '(', ''), ')', '') = ?
                  OR (? <> '' AND LOWER(cp.email) = ?))
           LIMIT 1
          ''',
          <Object?>[studentId, _schoolId, phone, email, email],
        );
        if (existing != null && SqlValue.asBool(existing['linked_to_student'])) {
          throw const ConflictFailure(
            message:
                'A contact with this phone or email is already linked to this student',
          );
        }
        if (existing != null) {
          await tx.execute(
            'INSERT INTO student_contacts (student_id, contact_id, relationship, is_primary) VALUES (?, ?, ?, ?)',
            <Object?>[studentId, existing['id'], c.relationship, c.isPrimary ? 1 : 0],
          );
          return 'Existing contact linked successfully';
        }

        final int? personId = await tx.insert(
          'INSERT INTO people (school_id, first_name, last_name, phone, email, address) VALUES (?, ?, ?, ?, ?, ?)',
          <Object?>[_schoolId, c.firstName, c.lastName, c.phone, c.email, c.address],
        );
        final int? contactId = await tx.insert(
          "INSERT INTO contacts (school_id, person_id, contact_type, occupation, alive_status) VALUES (?, ?, ?, ?, 'alive')",
          <Object?>[_schoolId, personId, c.contactType, c.occupation],
        );
        await tx.execute(
          'INSERT INTO student_contacts (student_id, contact_id, relationship, is_primary) VALUES (?, ?, ?, ?)',
          <Object?>[studentId, contactId, c.relationship, c.isPrimary ? 1 : 0],
        );
        return 'Phone number saved successfully';
      });
      return Ok<String>(outcome ?? 'Saved');
    } on Failure catch (failure) {
      return Err<String>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // PUT / DELETE /api/students/contacts/[id] — with the tenant check added
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<void>> updateContact(int contactId, ContactInput c) async {
    try {
      if (c.phone.trim().isEmpty) {
        return const Err<void>(
          ValidationFailure(message: 'Phone number is required'),
        );
      }
      final bool found = await _db.transaction((DbTransaction tx) async {
        final Row? contact = await tx.queryOne(
          'SELECT person_id FROM contacts WHERE id = ? AND school_id = ?',
          <Object?>[contactId, _schoolId],
        );
        if (contact == null) return false;
        await tx.execute(
          'UPDATE people SET first_name = ?, last_name = ?, phone = ?, email = ?, address = ? WHERE id = ?',
          <Object?>[
            c.firstName,
            c.lastName,
            c.phone,
            c.email,
            c.address,
            contact['person_id'],
          ],
        );
        await tx.execute(
          'UPDATE contacts SET occupation = ?, alive_status = ? WHERE id = ?',
          <Object?>[c.occupation, c.aliveStatus, contactId],
        );
        // The route renames the relationship on every learner this contact
        // is linked to — reproduced.
        if (c.relationship.isNotEmpty) {
          await tx.execute(
            'UPDATE student_contacts SET relationship = ? WHERE contact_id = ?',
            <Object?>[c.relationship, contactId],
          );
        }
        return true;
      });
      return found
          ? const Ok<void>(null)
          : const Err<void>(NotFoundFailure(message: 'Contact not found'));
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }

  @override
  Future<Result<void>> removeContact(int contactId) async {
    try {
      final bool found = await _db.transaction((DbTransaction tx) async {
        final Row? contact = await tx.queryOne(
          'SELECT person_id FROM contacts WHERE id = ? AND school_id = ?',
          <Object?>[contactId, _schoolId],
        );
        if (contact == null) return false;
        await tx.execute(
          'DELETE FROM student_contacts WHERE contact_id = ?',
          <Object?>[contactId],
        );
        await tx.execute(
          'UPDATE contacts SET deleted_at = NOW() WHERE id = ?',
          <Object?>[contactId],
        );
        await tx.execute(
          'UPDATE people SET deleted_at = NOW() WHERE id = ?',
          <Object?>[contact['person_id']],
        );
        return true;
      });
      return found
          ? const Ok<void>(null)
          : const Err<void>(NotFoundFailure(message: 'Contact not found'));
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/students/[id]/primary-contact
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<String>> setPrimaryContact(
    int studentId, {
    required String phone,
    String firstName = '',
    String lastName = '',
    String relationship = 'Guardian',
  }) async {
    try {
      if (phone.trim().isEmpty) {
        return const Err<String>(
          ValidationFailure(message: 'Phone number is required'),
        );
      }
      final String message = await _db.transaction((DbTransaction tx) async {
        final Row? student = await tx.queryOne(
          'SELECT school_id FROM students WHERE id = ? AND school_id = ? AND deleted_at IS NULL',
          <Object?>[studentId, _schoolId],
        );
        if (student == null) {
          throw const NotFoundFailure(message: 'Student not found');
        }
        final Row? existing = await tx.queryOne(
          '''
          SELECT sc.contact_id, c.person_id FROM student_contacts sc
            JOIN contacts c ON sc.contact_id = c.id
           WHERE sc.student_id = ? AND sc.is_primary = 1
          ''',
          <Object?>[studentId],
        );
        if (existing != null) {
          await tx.execute(
            'UPDATE people SET phone = ?, first_name = ?, last_name = ? WHERE id = ?',
            <Object?>[phone, firstName, lastName, existing['person_id']],
          );
          await tx.execute(
            'UPDATE student_contacts SET relationship = ? WHERE contact_id = ? AND student_id = ?',
            <Object?>[relationship, existing['contact_id'], studentId],
          );
          return 'Primary contact updated successfully';
        }
        final int? personId = await tx.insert(
          'INSERT INTO people (school_id, first_name, last_name, phone) VALUES (?, ?, ?, ?)',
          <Object?>[_schoolId, firstName, lastName, phone],
        );
        final int? contactId = await tx.insert(
          "INSERT INTO contacts (school_id, person_id, contact_type, alive_status) VALUES (?, ?, 'guardian', 'alive')",
          <Object?>[_schoolId, personId],
        );
        await tx.execute(
          'INSERT INTO student_contacts (student_id, contact_id, relationship, is_primary) VALUES (?, ?, ?, 1)',
          <Object?>[studentId, contactId, relationship],
        );
        return 'Primary contact created successfully';
      });
      return Ok<String>(message);
    } on Failure catch (failure) {
      return Err<String>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/students/duplicates
  // ───────────────────────────────────────────────────────────────────────

  static const String _memberSelect = '''
    SELECT s.id, p.first_name, p.last_name, s.admission_no, s.status,
           s.created_at, s.admission_date,
           CONCAT(LOWER(TRIM(p.first_name)), '|', LOWER(TRIM(p.last_name))) AS gkey,
           (SELECT c.name FROM enrollments e JOIN classes c ON c.id = e.class_id
             WHERE e.student_id = s.id AND e.status = 'active' ORDER BY e.id DESC LIMIT 1) AS class_name,
           (SELECT e.class_id FROM enrollments e
             WHERE e.student_id = s.id AND e.status = 'active' ORDER BY e.id DESC LIMIT 1) AS class_id,
           (SELECT COUNT(*) FROM enrollments en WHERE en.student_id = s.id) AS enrollment_count,
           (SELECT COUNT(*) FROM student_attendance sa WHERE sa.student_id = s.id) AS attendance_count,
           (SELECT COUNT(*) FROM results r WHERE r.student_id = s.id) AS results_count
      FROM students s
      JOIN people p ON s.person_id = p.id''';

  DuplicateMember _member(Row r) => DuplicateMember(
    id: SqlValue.asInt(r['id']) ?? 0,
    firstName: SqlValue.asString(r['first_name']),
    lastName: SqlValue.asString(r['last_name']),
    admissionNo: SqlValue.asString(r['admission_no']),
    className: SqlValue.asString(r['class_name']),
    classId: SqlValue.asInt(r['class_id']),
    status: SqlValue.asString(r['status']),
    createdAt: SqlValue.asString(r['created_at']),
    admissionDate: SqlValue.asString(r['admission_date']),
    enrollmentCount: SqlValue.asInt(r['enrollment_count']) ?? 0,
    attendanceCount: SqlValue.asInt(r['attendance_count']) ?? 0,
    resultsCount: SqlValue.asInt(r['results_count']) ?? 0,
  );

  @override
  Future<Result<DuplicateReport>> duplicates({int limit = 200}) async {
    try {
      final int lim = limit.clamp(1, 500);
      final List<Object?> school = <Object?>[_schoolId];

      // The route's group queries and total, issued together.
      final List<Object> heads = await Future.wait(<Future<Object>>[
        _db.query('''
          SELECT LOWER(TRIM(p.first_name)) AS fn, LOWER(TRIM(p.last_name)) AS ln, COUNT(*) AS cnt
            FROM students s JOIN people p ON s.person_id = p.id
           WHERE s.school_id = ? AND s.deleted_at IS NULL
           GROUP BY LOWER(TRIM(p.first_name)), LOWER(TRIM(p.last_name))
          HAVING COUNT(*) > 1
           ORDER BY COUNT(*) DESC
           LIMIT $lim''', school),
        _db.query('''
          SELECT s.admission_no, COUNT(*) AS cnt
            FROM students s
           WHERE s.school_id = ? AND s.deleted_at IS NULL
             AND s.admission_no IS NOT NULL AND s.admission_no != ''
           GROUP BY s.admission_no
          HAVING COUNT(*) > 1
           LIMIT $lim''', school),
        _db
            .queryOne(
              'SELECT COUNT(*) AS cnt FROM students WHERE school_id = ? AND deleted_at IS NULL',
              school,
            )
            .then((Row? r) => SqlValue.asInt(r?['cnt']) ?? 0),
      ]);
      final List<Row> nameGroups = heads[0] as List<Row>;
      final List<Row> admGroups = heads[1] as List<Row>;

      final List<String> nameKeys = <String>[
        for (final Row g in nameGroups)
          '${SqlValue.asString(g['fn']) ?? ''}|${SqlValue.asString(g['ln']) ?? ''}',
      ];
      final List<String> admNos = <String>[
        for (final Row g in admGroups) SqlValue.asString(g['admission_no']) ?? '',
      ];

      // The route fetches each group's members separately — one round trip
      // per group. Here every member comes back in at most two statements.
      final List<List<Row>> members = await Future.wait(<Future<List<Row>>>[
        nameKeys.isEmpty
            ? Future<List<Row>>.value(const <Row>[])
            : _db.query(
                '$_memberSelect WHERE s.school_id = ? AND s.deleted_at IS NULL '
                "AND CONCAT(LOWER(TRIM(p.first_name)), '|', LOWER(TRIM(p.last_name))) "
                'IN (${_marks(nameKeys.length)}) '
                'ORDER BY s.created_at ASC',
                <Object?>[_schoolId, ...nameKeys],
              ),
        admNos.isEmpty
            ? Future<List<Row>>.value(const <Row>[])
            : _db.query(
                '$_memberSelect WHERE s.school_id = ? AND s.deleted_at IS NULL '
                'AND s.admission_no IN (${_marks(admNos.length)}) '
                'ORDER BY s.created_at ASC',
                <Object?>[_schoolId, ...admNos],
              ),
      ]);

      final Map<String, List<DuplicateMember>> byName =
          <String, List<DuplicateMember>>{};
      for (final Row r in members[0]) {
        byName
            // The key SQL computed, so MySQL's TRIM/LOWER decide grouping
            // exactly as they did in the GROUP BY — Dart's differ on tabs
            // and some non-ASCII letters.
            .putIfAbsent(
              SqlValue.asString(r['gkey']) ?? '',
              () => <DuplicateMember>[],
            )
            .add(_member(r));
      }
      final Map<String, List<DuplicateMember>> byAdm =
          <String, List<DuplicateMember>>{};
      for (final Row r in members[1]) {
        byAdm
            .putIfAbsent(
              SqlValue.asString(r['admission_no']) ?? '',
              () => <DuplicateMember>[],
            )
            .add(_member(r));
      }

      return Ok<DuplicateReport>(
        DuplicateReport(
          totalStudents: heads[2] as int,
          groups: buildDuplicateGroups(
            nameKeys: nameKeys,
            membersByName: byName,
            admissionNos: admNos,
            membersByAdmission: byAdm,
          ),
        ),
      );
    } on Failure catch (failure) {
      return Err<DuplicateReport>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/students/duplicates/merge
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<List<MergeOutcome>>> merge(
    List<({int primaryId, List<int> secondaryIds})> groups,
  ) async {
    for (final ({int primaryId, List<int> secondaryIds}) g in groups) {
      if (g.secondaryIds.isEmpty) {
        return const Err<List<MergeOutcome>>(
          ValidationFailure(
            message: 'Each group must have primary_id and non-empty secondary_ids',
          ),
        );
      }
      if (g.secondaryIds.contains(g.primaryId)) {
        return const Err<List<MergeOutcome>>(
          ValidationFailure(message: 'Cannot merge student with itself'),
        );
      }
    }

    final List<MergeOutcome> results = <MergeOutcome>[];
    for (final ({int primaryId, List<int> secondaryIds}) g in groups) {
      try {
        final List<String> actions = await _db.transaction(
          (DbTransaction tx) => _mergeGroup(tx, g.primaryId, g.secondaryIds),
        );
        results.add(MergeOutcome(primaryId: g.primaryId, success: true, actions: actions));
        await _audit.write(
          schoolId: _schoolId,
          userId: _userId,
          action: 'MERGED_STUDENTS',
          entityType: 'student',
          entityId: g.primaryId,
          details: <String, Object?>{
            'secondary_ids': g.secondaryIds,
            'actions': actions,
          },
        );
      } on Failure catch (failure) {
        results.add(
          MergeOutcome(
            primaryId: g.primaryId,
            success: false,
            error: failure.message,
          ),
        );
      }
    }
    return Ok<List<MergeOutcome>>(results);
  }

  /// Runs [sql] and treats a failure as "this table does not exist here", as
  /// the route's `try { … } catch {}` blocks do.
  static Future<int> _optional(
    DbTransaction tx,
    String sql,
    List<Object?> params,
  ) async {
    try {
      return await tx.execute(sql, params);
    } on Failure {
      return 0;
    }
  }

  Future<List<String>> _mergeGroup(
    DbTransaction tx,
    int primaryId,
    List<int> secondaryIds,
  ) async {
    final List<String> actions = <String>[];
    final Row? primary = await tx.queryOne(
      'SELECT s.id FROM students s WHERE s.id = ? AND s.school_id = ? AND s.deleted_at IS NULL',
      <Object?>[primaryId, _schoolId],
    );
    if (primary == null) {
      throw ServerFailure(message: 'Primary student #$primaryId not found');
    }

    for (final int secondaryId in secondaryIds) {
      final Row? secondary = await tx.queryOne(
        'SELECT s.id FROM students s WHERE s.id = ? AND s.school_id = ? AND s.deleted_at IS NULL',
        <Object?>[secondaryId, _schoolId],
      );
      if (secondary == null) {
        actions.add('Skipped #$secondaryId — not found or already deleted');
        continue;
      }

      // Enrolments: move, unless the primary already has that class + year.
      final Set<String> existing = <String>{
        for (final Row e in await tx.query(
          'SELECT class_id, academic_year_id FROM enrollments WHERE student_id = ? AND school_id = ?',
          <Object?>[primaryId, _schoolId],
        ))
          '${e['class_id']}-${e['academic_year_id']}',
      };
      int moved = 0;
      for (final Row e in await tx.query(
        'SELECT id, class_id, academic_year_id FROM enrollments WHERE student_id = ? AND school_id = ?',
        <Object?>[secondaryId, _schoolId],
      )) {
        if (existing.contains('${e['class_id']}-${e['academic_year_id']}')) {
          await tx.execute(
            "UPDATE enrollments SET status = 'closed', end_reason = 'merged_duplicate' WHERE id = ? AND school_id = ?",
            <Object?>[e['id'], _schoolId],
          );
        } else {
          await tx.execute(
            'UPDATE enrollments SET student_id = ? WHERE id = ? AND school_id = ?',
            <Object?>[primaryId, e['id'], _schoolId],
          );
          moved++;
        }
      }
      if (moved > 0) actions.add('Transferred $moved enrollments from #$secondaryId');

      // The legacy attendance table, as the route moves it. The canonical
      // attendance (attendance_records / attendance_raw_events, keyed by
      // person_id) and biometric enrolments are NOT moved — see PARITY.
      final int att = await tx.execute(
        'UPDATE student_attendance SET student_id = ? WHERE student_id = ? AND school_id = ?',
        <Object?>[primaryId, secondaryId, _schoolId],
      );
      if (att > 0) actions.add('Transferred $att attendance records from #$secondaryId');

      final int zk = await _optional(
        tx,
        'UPDATE zk_attendance_logs SET student_id = ? WHERE student_id = ? AND school_id = ?',
        <Object?>[primaryId, secondaryId, _schoolId],
      );
      if (zk > 0) actions.add('Transferred $zk ZK attendance logs from #$secondaryId');

      final int res = await tx.execute(
        'UPDATE results SET student_id = ? WHERE student_id = ? AND school_id = ?',
        <Object?>[primaryId, secondaryId, _schoolId],
      );
      if (res > 0) actions.add('Transferred $res results from #$secondaryId');

      final int fees = await _optional(
        tx,
        'UPDATE learner_fees SET student_id = ? WHERE student_id = ? AND school_id = ?',
        <Object?>[primaryId, secondaryId, _schoolId],
      );
      if (fees > 0) actions.add('Transferred $fees fee records from #$secondaryId');

      // Contacts are NOT moved. The route's statement for them contains no
      // `school_id`, so its tenant guard (assertTenantSafe) rejects it and
      // the surrounding try/catch swallows the error: on the platform, a
      // merged duplicate's contacts stay on the archived record. Reproduced.

      final int promos = await _optional(
        tx,
        'UPDATE promotions SET student_id = ? WHERE student_id = ? AND school_id = ?',
        <Object?>[primaryId, secondaryId, _schoolId],
      );
      if (promos > 0) actions.add('Transferred $promos promotions from #$secondaryId');

      await tx.execute(
        "UPDATE students SET deleted_at = NOW(), notes = CONCAT(COALESCE(notes, ''), '\n[MERGED INTO #', ?, ' on ', NOW(), ']') WHERE id = ? AND school_id = ?",
        <Object?>['$primaryId', secondaryId, _schoolId],
      );
      actions.add('Soft-deleted duplicate #$secondaryId');
    }
    return actions;
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/enrollments/bulk — mode: promote
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<int>> promoteClass({
    required int fromClassId,
    required int toClassId,
    required int academicYearId,
    int? termId,
    List<int> studentIds = const <int>[],
  }) async {
    try {
      int? term = termId;
      if (term == null) {
        term = (await currentTerm(_db, _schoolId))?.id;
        if (term == null) {
          return const Err<int>(ValidationFailure(message: 'No active term found'));
        }
      }
      final int resolvedTerm = term;

      final int promoted = await _db.transaction((DbTransaction tx) async {
        List<int> ids = studentIds;
        if (ids.isEmpty) {
          ids = <int>[
            for (final Row r in await tx.query(
              '''
              SELECT DISTINCT e.student_id FROM enrollments e
               WHERE e.school_id = ? AND e.class_id = ? AND e.status = 'active' AND e.deleted_at IS NULL
              ''',
              <Object?>[_schoolId, fromClassId],
            ))
              ?SqlValue.asInt(r['student_id']),
          ];
        }
        if (ids.isEmpty) return 0;

        await tx.execute(
          "UPDATE enrollments SET status = 'completed', end_date = CURDATE(), end_reason = 'promoted', updated_at = NOW() "
          "WHERE school_id = ? AND student_id IN (${_marks(ids.length)}) AND status = 'active'",
          <Object?>[_schoolId, ...ids],
        );
        for (final int sid in ids) {
          await tx.execute(
            '''
            INSERT INTO enrollments
              (school_id, student_id, class_id, academic_year_id, term_id,
               enrollment_type, status, joined_at, enrollment_date, created_at)
            VALUES (?, ?, ?, ?, ?, 'continuing', 'active', CURDATE(), CURDATE(), NOW())
            ON DUPLICATE KEY UPDATE status='active', updated_at=NOW()
            ''',
            <Object?>[_schoolId, sid, toClassId, academicYearId, resolvedTerm],
          );
        }
        for (final int sid in ids) {
          await tx.execute(
            '''
            INSERT INTO promotions
              (school_id, student_id, from_class_id, to_class_id,
               from_academic_year_id, to_academic_year_id,
               promotion_status, approval_status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 'promoted', 'approved', NOW())
            ON DUPLICATE KEY UPDATE promotion_status='promoted', updated_at=NOW()
            ''',
            <Object?>[_schoolId, sid, fromClassId, toClassId, academicYearId, academicYearId],
          );
        }
        return ids.length;
      });
      _logger.info('Promoted a class.', context: <String, Object?>{'count': promoted});
      return Ok<int>(promoted);
    } on Failure catch (failure) {
      return Err<int>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // POST /api/enrollments/bulk — mode: multiple_students
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<BulkEnrollResult>> enrollMany({
    required List<int> studentIds,
    required int classId,
    required int academicYearId,
    required int termId,
    required int studyModeId,
    required int curriculumId,
    required int programId,
    required EnrollmentDecision decision,
    int? streamId,
  }) async {
    try {
      if (studentIds.isEmpty) {
        return const Err<BulkEnrollResult>(
          ValidationFailure(message: 'student_ids must be a non-empty array'),
        );
      }
      final List<Row?> found = await Future.wait(<Future<Row?>>[
        _db.queryOne(
          'SELECT id, name FROM classes WHERE id = ? AND school_id = ? LIMIT 1',
          <Object?>[classId, _schoolId],
        ),
        _db.queryOne(
          'SELECT id, name FROM programs WHERE id = ? AND school_id = ? AND is_active = 1 LIMIT 1',
          <Object?>[programId, _schoolId],
        ),
      ]);
      if (found[0] == null) {
        return const Err<BulkEnrollResult>(NotFoundFailure(message: 'Class not found'));
      }
      if (found[1] == null) {
        return const Err<BulkEnrollResult>(
          NotFoundFailure(message: 'Program not found or inactive'),
        );
      }

      // One transaction per learner, so one failure leaves the rest.
      final List<BulkEnrollItem> items = <BulkEnrollItem>[];
      for (final int sid in studentIds) {
        try {
          final String? name = await _db.transaction((DbTransaction tx) async {
            final Row? s = await tx.queryOne(
              'SELECT s.id, p.first_name, p.last_name FROM students s JOIN people p ON s.person_id = p.id '
              'WHERE s.id = ? AND s.school_id = ? AND s.deleted_at IS NULL LIMIT 1',
              <Object?>[sid, _schoolId],
            );
            if (s == null) return null;
            // The web bulk form always sends close_previous: true.
            await tx.execute(
              "UPDATE enrollments SET status = 'completed', end_date = CURDATE(), end_reason = 'promoted', updated_at = NOW() "
              "WHERE student_id = ? AND school_id = ? AND status = 'active'",
              <Object?>[sid, _schoolId],
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
                sid,
                classId,
                streamId,
                academicYearId,
                termId,
                studyModeId,
                curriculumId,
                programId,
                decision.enrollmentType,
              ],
            );
            await tx.execute(
              'INSERT IGNORE INTO enrollment_programs (enrollment_id, program_id) VALUES (?, ?)',
              <Object?>[enrollmentId, programId],
            );
            return '${SqlValue.asString(s['first_name']) ?? ''} ${SqlValue.asString(s['last_name']) ?? ''}';
          });
          items.add(
            name == null
                ? BulkEnrollItem(studentId: sid, success: false, message: 'Student not found')
                : BulkEnrollItem(
                    studentId: sid,
                    success: true,
                    message: '$name enrolled successfully',
                  ),
          );
        } on Failure catch (failure) {
          items.add(
            BulkEnrollItem(studentId: sid, success: false, message: failure.message),
          );
        }
      }
      return Ok<BulkEnrollResult>(BulkEnrollResult(items: items));
    } on Failure catch (failure) {
      return Err<BulkEnrollResult>(failure);
    }
  }
}
