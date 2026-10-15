import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/features/attendance/data/direct/longterm/confidence_scoring.dart';
import 'package:drais/features/attendance/data/direct/longterm/gender_filter.dart';
import 'package:drais/features/attendance/data/direct/longterm/person_intelligence.dart';
import 'package:drais/features/attendance/data/direct/longterm/school_time.dart';
import 'package:drais/features/attendance/domain/entities/attendance_history.dart';
import 'package:drais/features/attendance/domain/entities/attendance_insights.dart';
import 'package:drais/features/attendance/domain/repositories/attendance_repository.dart';

/// Attendance, read straight from TiDB — DRAIS LongTerm's read routes, in
/// Dart.
///
/// ## What this is
///
/// In direct mode the app is its own backend, so this class *is* the route
/// handlers. Each public method reproduces one LongTerm route: the same SQL,
/// the same filters, the same fallbacks, the same quirks. The source is cited
/// on every method; when the platform changes, diff against it.
///
/// ## Tenant scope is the whole game here
///
/// There is no server applying `getSessionSchoolId()`, so **every query below
/// takes `schoolId` from the validated session** and filters on it. Not from a
/// screen, not from a dropdown. `attendance_raw_events` carries its own
/// `school_id`, which is the only scope that works for an *unmatched* punch.
///
/// ## Deliberately not reproduced
///
/// `/api/attendance/history` also runs `autoCorrectDay()` — a clock repair
/// that **rewrites `punch_at`** during a read — plus a Sentinel anomaly hook
/// and an export audit. All three are side effects, not reads, and are left to
/// the web app; see `docs/PARITY.md`. Times shown here are therefore the
/// stored times, corrected only once someone has opened the web logs page.
class AttendanceDirectRepository implements AttendanceRepository {
  /// Creates the repository.
  AttendanceDirectRepository({
    required DraisDatabase database,
    required int schoolId,
    required AppLogger logger,
  }) : _db = database,
       _schoolId = schoolId,
       _logger = logger.child('AttendanceDirect');

  final DraisDatabase _db;

  /// The trusted school id, taken from the session at construction.
  final int _schoolId;

  final AppLogger _logger;

  ({String timezone, int offsetMinutes})? _policy;
  DateTime? _policyExpiry;

  // ───────────────────────────────────────────────────────────────────────
  // resolveTimePolicy() — src/lib/attendance/device-clock.ts
  // ───────────────────────────────────────────────────────────────────────

  /// The school's timezone and UTC offset, cached for a minute as the
  /// platform does. Only the two fields reads need are loaded.
  Future<({String timezone, int offsetMinutes})> _timePolicy() async {
    final DateTime now = DateTime.now();
    final ({String timezone, int offsetMinutes})? cached = _policy;
    if (cached != null && _policyExpiry != null && now.isBefore(_policyExpiry!)) {
      return cached;
    }

    ({String timezone, int offsetMinutes}) policy = (
      timezone: 'Africa/Kampala',
      offsetMinutes: defaultOffsetMinutes,
    );
    try {
      final Row? row = await _db.queryOne(
        'SELECT school_timezone, utc_offset_minutes '
        'FROM attendance_time_policy WHERE school_id = ? LIMIT 1',
        <Object?>[_schoolId],
      );
      if (row != null) {
        policy = (
          timezone: SqlValue.asString(row['school_timezone']) ?? 'Africa/Kampala',
          offsetMinutes:
              SqlValue.asInt(row['utc_offset_minutes']) ?? defaultOffsetMinutes,
        );
      }
    } on Failure {
      // Table not migrated yet → defaults, exactly as the platform.
    }

    _policy = policy;
    _policyExpiry = now.add(const Duration(minutes: 1));
    return policy;
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/attendance/history — src/app/api/attendance/history/route.ts
  // ───────────────────────────────────────────────────────────────────────

  /// Sort whitelist — never interpolate user input into ORDER BY.
  static const Map<HistorySort, String> _sortable = <HistorySort, String>{
    HistorySort.time: 'ar.punch_at',
    HistorySort.name:
        "COALESCE(NULLIF(ar.display_name,''), "
        "NULLIF(TRIM(CONCAT_WS(' ', p.first_name, p.last_name)),''), "
        "dud.device_name, '')",
    HistorySort.pin: 'CAST(ar.device_user_id AS UNSIGNED)',
    HistorySort.device: 'ar.device_sn',
    HistorySort.status: 'ar.derived_event',
    HistorySort.type: 'ar.role_type',
  };

  static const String _dudJoin = '''
    LEFT JOIN device_user_directory dud
      ON dud.school_id = ar.school_id
     AND dud.device_sn = ar.device_sn
     AND dud.device_user_id = CAST(ar.device_user_id AS CHAR)''';

  @override
  Future<Result<AttendanceHistoryPage>> history(
    AttendanceHistoryQuery q,
  ) async {
    try {
      final ({String timezone, int offsetMinutes}) policy = await _timePolicy();
      final int offset = policy.offsetMinutes;
      final int limit = q.limit.clamp(1, 250);
      final int page = q.page < 1 ? 1 : q.page;

      final List<String> conditions = <String>['ar.school_id = ?'];
      final List<Object?> params = <Object?>[_schoolId];

      // Intra-day window. With no date, the window means TODAY — the route
      // calls schoolLocalToday() with its default offset, reproduced as is.
      String defaultDay() => q.dateFrom ?? q.dateTo ?? schoolLocalToday();
      final String? timeFrom = q.timeframe.from;
      final String? timeTo = q.timeframe.to;

      if (isHhMm(timeFrom)) {
        conditions.add('ar.punch_at >= ?');
        params.add(
          timeBoundary(
            q.dateFrom ?? defaultDay(),
            timeFrom!,
            endOfMinute: false,
            offsetMinutes: offset,
          ),
        );
      } else if (q.dateFrom != null) {
        conditions.add('ar.punch_at >= ?');
        params.add(
          toUtcBoundary(q.dateFrom!, end: false, offsetMinutes: offset),
        );
      }
      if (isHhMm(timeTo)) {
        conditions.add('ar.punch_at <= ?');
        params.add(
          timeBoundary(
            q.dateTo ?? defaultDay(),
            timeTo!,
            endOfMinute: true,
            offsetMinutes: offset,
          ),
        );
      } else if (q.dateTo != null) {
        conditions.add('ar.punch_at <= ?');
        params.add(toUtcBoundary(q.dateTo!, end: true, offsetMinutes: offset));
      }

      if (q.deviceSn != null && q.deviceSn!.isNotEmpty) {
        conditions.add('ar.device_sn = ?');
        params.add(q.deviceSn);
      }
      if (q.matched != null) {
        conditions.add('ar.matched = ?');
        params.add(q.matched! ? 1 : 0);
      }

      // Strict tab semantics, kept separate from the base filters so the
      // badge counts can be computed without the tab selector.
      final String tabWhere = switch (q.tab) {
        HistoryTab.learners => "ar.role_type = 'student' AND ar.matched = 1",
        HistoryTab.staff => "ar.role_type = 'staff' AND ar.matched = 1",
        HistoryTab.unmatched => '(ar.matched = 0 OR ar.person_id IS NULL)',
        HistoryTab.all => '',
      };

      final String? search = q.search?.trim();
      if (search != null && search.isNotEmpty) {
        conditions.add(
          '(LOWER(ar.device_user_id) LIKE ? OR LOWER(ar.display_name) LIKE ? '
          'OR LOWER(p.first_name) LIKE ? OR LOWER(p.last_name) LIKE ? '
          'OR LOWER(dud.device_name) LIKE ?)',
        );
        final String s = '%${search.toLowerCase()}%';
        params.addAll(<Object?>[s, s, s, s, s]);
      }
      if (q.classId != null) {
        conditions.add('''EXISTS (
          SELECT 1 FROM students s JOIN enrollments e ON e.student_id = s.id
           WHERE s.person_id = ar.person_id AND e.status = 'active'
             AND e.class_id = ?)''');
        params.add(q.classId);
      }
      if (q.streamId != null && q.streamId! > 0) {
        conditions.add('''EXISTS (
          SELECT 1 FROM students s JOIN enrollments e ON e.student_id = s.id
           WHERE s.person_id = ar.person_id AND s.school_id = ?
             AND e.status = 'active' AND e.stream_id = ?)''');
        params.addAll(<Object?>[_schoolId, q.streamId]);
      }
      if (q.residence == 'day' || q.residence == 'boarding') {
        // Unclassified learners count as day scholars, as on the dashboard.
        conditions.add('''EXISTS (
          SELECT 1 FROM students s
           WHERE s.person_id = ar.person_id AND s.school_id = ?
             AND COALESCE(NULLIF(s.residency_status, ''), 'day') = ?)''');
        params.addAll(<Object?>[_schoolId, q.residence]);
      }
      if (isGenderFilter(q.gender)) {
        final ({String sql, List<String> params}) g = genderMatchSql(
          'p.gender',
          q.gender!,
        );
        conditions.add(g.sql);
        params.addAll(g.params);
      }
      if (q.personId != null) {
        conditions.add('ar.person_id = ?');
        params.add(q.personId);
      }
      switch (q.derived) {
        case DerivedFilter.late:
          conditions.add("ar.derived_event = 'ARRIVED_LATE'");
        case DerivedFilter.early:
          conditions.add("ar.derived_event = 'ARRIVED_EARLY'");
        case DerivedFilter.onTime:
          conditions.add("ar.derived_event IN ('ARRIVED','ARRIVED_EARLY')");
        case DerivedFilter.none:
          break;
      }

      final String baseWhere = conditions.join(' AND ');
      final String where = tabWhere.isEmpty
          ? baseWhere
          : '$baseWhere AND $tabWhere';

      final String sortCol = _sortable[q.sort]!;
      final String sortDir = q.ascending ? 'ASC' : 'DESC';
      final String orderBy =
          '$sortCol $sortDir'
          '${q.sort != HistorySort.time ? ', ar.punch_at DESC' : ''}';

      // The route runs COUNT(where) and the tab badges (baseWhere) as two
      // statements. Over a phone link every statement is a round trip, so
      // both are taken in one pass: `total` is the tab clause summed under the
      // base filters, which counts exactly the rows `COUNT(*) … WHERE where`
      // would.
      final String totalExpr = tabWhere.isEmpty
          ? 'COUNT(*)'
          : 'SUM(CASE WHEN $tabWhere THEN 1 ELSE 0 END)';

      final Future<Row?> countsFuture = _db.queryOne('''
        SELECT
          $totalExpr AS total,
          COUNT(*) AS total_all,
          SUM(CASE WHEN ar.role_type = 'student' AND ar.matched = 1 THEN 1 ELSE 0 END) AS total_learners,
          SUM(CASE WHEN ar.role_type = 'staff' AND ar.matched = 1 THEN 1 ELSE 0 END) AS total_staff,
          SUM(CASE WHEN ar.matched = 0 OR ar.person_id IS NULL THEN 1 ELSE 0 END) AS total_unmatched
        FROM attendance_raw_events ar
        LEFT JOIN people p ON ar.person_id = p.id
        $_dudJoin
        WHERE $baseWhere
        ''', params);

      final Future<List<Row>> rowsFuture = _db.query('''
        SELECT
          ar.id,
          ar.device_sn,
          CAST(ar.device_user_id AS CHAR) AS device_user_id,
          ar.punch_at AS check_time,
          ar.verify_type,
          ar.io_mode,
          ar.derived_event,
          ar.derived_detail,
          ar.matched,
          ar.is_provisional,
          ar.role_type,
          ar.display_name,
          ar.person_id,
          ar.source,
          ar.resolution_score,
          ar.resolution_path,
          ar.time_source,
          ar.clock_skew_seconds,
          d.device_name,
          d.location AS device_location,
          d.is_online AS device_online,
          dch.confidence AS clock_confidence,
          dud.device_name AS device_known_name,
          rec.rule_id AS rec_rule_id,
          (rec.id IS NOT NULL) AS has_verdict,
          (SELECT c2.name
             FROM enrollments e2
             LEFT JOIN programs pr2 ON pr2.id = e2.program_id
             JOIN classes c2 ON c2.id = e2.class_id
            WHERE e2.student_id = s.id AND e2.status = 'active'
            ORDER BY pr2.is_default DESC, e2.id DESC
            LIMIT 1) AS class_name,
          (SELECT ob2.status
             FROM notification_outbox ob2
            WHERE ob2.school_id = ar.school_id
              AND ob2.subject_person_id = ar.person_id
              AND DATE(ob2.created_at) = DATE(ar.punch_at)
            ORDER BY ob2.created_at DESC
            LIMIT 1) AS sms_status,
          p.first_name,
          p.last_name,
          p.photo_url,
          p.gender,
          s.admission_no,
          stf.position AS staff_position,
          dep.name AS staff_department
        FROM attendance_raw_events ar
        LEFT JOIN devices d ON ar.device_sn = d.sn
        LEFT JOIN people p ON ar.person_id = p.id
        LEFT JOIN staff stf ON ar.role_type = 'staff' AND stf.person_id = ar.person_id
              AND stf.school_id = ar.school_id AND stf.deleted_at IS NULL
        LEFT JOIN departments dep ON dep.id = stf.department_id
        LEFT JOIN students s ON p.id = s.person_id AND s.school_id = ar.school_id
        $_dudJoin
        LEFT JOIN device_clock_health dch
          ON dch.school_id = ar.school_id AND dch.device_sn = ar.device_sn
         AND dch.local_date = DATE(DATE_ADD(ar.punch_at, INTERVAL 180 MINUTE))
        LEFT JOIN attendance_records rec
          ON rec.school_id = ar.school_id AND rec.person_id = ar.person_id
         AND rec.attendance_date = DATE(DATE_ADD(ar.punch_at, INTERVAL 180 MINUTE))
        WHERE $where
        ORDER BY $orderBy
        ${DraisDatabase.limitClause(limit: limit, offset: (page - 1) * limit)}
        ''', params);

      final Row? counts = await countsFuture;
      final List<Row> rows = await rowsFuture;

      _logger.debug(
        'Loaded attendance history.',
        context: <String, Object?>{
          'tab': q.tab.wireValue,
          'rows': rows.length,
          'page': page,
        },
      );

      return Ok<AttendanceHistoryPage>(
        AttendanceHistoryPage(
          rows: rows.map(_toHistoryRow).toList(growable: false),
          tabCounts: HistoryTabCounts(
            all: SqlValue.asInt(counts?['total_all']) ?? 0,
            learners: SqlValue.asInt(counts?['total_learners']) ?? 0,
            staff: SqlValue.asInt(counts?['total_staff']) ?? 0,
            unmatched: SqlValue.asInt(counts?['total_unmatched']) ?? 0,
          ),
          page: page,
          limit: limit,
          total: SqlValue.asInt(counts?['total']) ?? 0,
          timezone: policy.timezone,
          offsetMinutes: offset,
        ),
      );
    } on Failure catch (failure) {
      return Err<AttendanceHistoryPage>(failure);
    }
  }

  /// The route's per-row enrichment: name fallback chain, provisional rule
  /// and `scoreRecord()`.
  AttendanceHistoryRow _toHistoryRow(Row row) {
    String? nonEmpty(Object? v) {
      final String? s = SqlValue.asString(v);
      return (s == null || s.isEmpty) ? null : s;
    }

    final bool matched = SqlValue.asBool(row['matched']);
    final int? personId = SqlValue.asInt(row['person_id']);
    final String? firstName = nonEmpty(row['first_name']);
    final String? lastName = nonEmpty(row['last_name']);
    final String? deviceName = nonEmpty(row['device_name']);
    final String? deviceKnownName = nonEmpty(row['device_known_name']);
    final int? skew = SqlValue.asInt(row['clock_skew_seconds']);
    final String? timeSource = nonEmpty(row['time_source']);
    final double? clockConfidence = SqlValue.asDouble(row['clock_confidence']);
    final String? roleType = nonEmpty(row['role_type']);
    final Object? online = row['device_online'];

    final String? personName =
        nonEmpty(row['display_name']) ??
        (firstName != null || lastName != null
            ? <String?>[firstName, lastName].whereType<String>().join(' ')
            : deviceKnownName);

    final RecordConfidence confidence = scoreRecord(
      ConfidenceInput(
        matched: matched,
        personId: personId,
        isProvisional: SqlValue.asBool(row['is_provisional']),
        resolutionScore: SqlValue.asDouble(row['resolution_score']),
        resolutionPath: nonEmpty(row['resolution_path']),
        deviceSn: nonEmpty(row['device_sn']),
        deviceKnown: deviceName != null || deviceKnownName != null,
        deviceOnline: online == null ? null : SqlValue.asBool(online),
        timeSource: timeSource,
        clockSkewSeconds: skew,
        clockConfidence: clockConfidence,
        wasCorrected:
            (skew ?? 0) != 0 &&
            timeSource == 'device' &&
            clockConfidence != null &&
            clockConfidence >= 85,
        hasVerdict: SqlValue.asBool(row['has_verdict']),
        ruleId: SqlValue.asInt(row['rec_rule_id']),
        derivedEvent: nonEmpty(row['derived_event']),
      ),
    );

    return AttendanceHistoryRow(
      id: SqlValue.asInt(row['id']) ?? 0,
      // punch_at is NOT NULL; the fallback keeps one bad row from taking the
      // screen down.
      checkTime:
          SqlValue.asUtcInstant(row['check_time']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      matched: matched,
      isProvisional:
          SqlValue.asBool(row['is_provisional']) ||
          (personId == null && !matched),
      personType: roleType ?? 'unmatched',
      confidence: confidence,
      deviceSn: nonEmpty(row['device_sn']),
      deviceUserId: nonEmpty(row['device_user_id']),
      verifyType: nonEmpty(row['verify_type']),
      ioMode: SqlValue.asInt(row['io_mode']),
      derivedEvent: nonEmpty(row['derived_event']),
      derivedDetail: nonEmpty(row['derived_detail']),
      roleType: roleType,
      personName: personName,
      personId: personId,
      source: nonEmpty(row['source']),
      resolutionPath: nonEmpty(row['resolution_path']),
      clockSkewSeconds: skew,
      deviceName: deviceName ?? deviceKnownName,
      deviceLocation: nonEmpty(row['device_location']),
      className: nonEmpty(row['class_name']),
      smsStatus: nonEmpty(row['sms_status']),
      firstName: firstName,
      lastName: lastName,
      photoUrl: nonEmpty(row['photo_url']),
      gender: nonEmpty(row['gender']),
      admissionNo: nonEmpty(row['admission_no']),
      staffPosition: nonEmpty(row['staff_position']),
      staffDepartment: nonEmpty(row['staff_department']),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // getDashboardAttendanceCounts() — src/lib/attendance/dashboard-counts.ts
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<DashboardAttendanceCounts>> dashboardCounts({
    String? date,
  }) async {
    try {
      final int offset = (await _timePolicy()).offsetMinutes;
      final String day = date ?? schoolLocalToday(offsetMinutes: offset);
      final String utcStart = utcDayStart(day, offset);
      final String utcEnd = utcDayStart(day, offset, 1);

      // Each lookup swallows its own failure, as the platform does: one
      // missing table must not blank the whole card.
      Future<int> total(String sql) async {
        try {
          final Row? r = await _db.queryOne(sql, <Object?>[_schoolId]);
          return SqlValue.asInt(r?['total']) ?? 0;
        } on Failure {
          return 0;
        }
      }

      final List<Object> results = await Future.wait(<Future<Object>>[
        _roleCounts('student', day, offset, utcStart, utcEnd),
        _roleCounts('staff', day, offset, utcStart, utcEnd),
        total(
          'SELECT COUNT(DISTINCT s.id) AS total FROM students s '
          "JOIN enrollments e ON s.id = e.student_id AND e.status = 'active' "
          "WHERE s.school_id = ? AND s.status = 'active' AND s.deleted_at IS NULL",
        ),
        total(
          'SELECT COUNT(*) AS total FROM staff '
          "WHERE school_id = ? AND status = 'active' AND deleted_at IS NULL",
        ),
      ]);

      final ({int present, int late}) stu =
          results[0] as ({int present, int late});
      final ({int present, int late}) stf =
          results[1] as ({int present, int late});
      final int studentTotal = results[2] as int;
      final int staffTotal = results[3] as int;

      int floor0(int n) => n < 0 ? 0 : n;

      return Ok<DashboardAttendanceCounts>(
        DashboardAttendanceCounts(
          date: day,
          students: RoleCounts(
            total: studentTotal,
            present: stu.present,
            late: stu.late,
            absent: floor0(studentTotal - stu.present),
          ),
          staff: RoleCounts(
            total: staffTotal,
            present: stf.present,
            late: stf.late,
            absent: floor0(staffTotal - stf.present),
          ),
        ),
      );
    } on Failure catch (failure) {
      return Err<DashboardAttendanceCounts>(failure);
    }
  }

  /// Distinct matched people with a punch in the day window, and how many of
  /// them first punched after the role's cutoff.
  Future<({int present, int late})> _roleCounts(
    String role,
    String date,
    int offset,
    String utcStart,
    String utcEnd,
  ) async {
    try {
      final String cutoff = await _roleLateCutoff(role, date);
      final Row? r = await _db.queryOne(
        '''
        SELECT
          COUNT(*) AS present,
          SUM(CASE WHEN TIME(DATE_ADD(first_at, INTERVAL ? MINUTE)) > ? THEN 1 ELSE 0 END) AS late
        FROM (
          SELECT role_ref_id, MIN(punch_at) AS first_at
            FROM attendance_raw_events
           WHERE school_id = ? AND matched = 1 AND role_type = ?
             AND role_ref_id IS NOT NULL
             AND punch_at >= ? AND punch_at < ?
           GROUP BY role_ref_id
        ) t
        ''',
        <Object?>[offset, cutoff, _schoolId, role, utcStart, utcEnd],
      );
      return (
        present: SqlValue.asInt(r?['present']) ?? 0,
        late: SqlValue.asInt(r?['late']) ?? 0,
      );
    } on Failure {
      return (present: 0, late: 0);
    }
  }

  /// The role's late cutoff from the school's own active rules for [date]:
  /// role-specific beats `all`, then priority, then the weekday override.
  Future<String> _roleLateCutoff(String role, String date) async {
    final String applies = role == 'staff'
        ? "('staff','teachers','all')"
        : "('students','learners','all')";
    try {
      final Row? rule = await _db.queryOne(
        '''
        SELECT id, arrival_end_time, late_threshold_minutes
          FROM attendance_rules
         WHERE school_id = ? AND is_active = 1 AND applies_to IN $applies
         ORDER BY (applies_to = 'all') ASC, priority ASC, id DESC LIMIT 1
        ''',
        <Object?>[_schoolId],
      );
      final String? arrivalEnd = SqlValue.asString(rule?['arrival_end_time']);
      if (rule != null && arrivalEnd != null && arrivalEnd.isNotEmpty) {
        final int id = SqlValue.asInt(rule['id']) ?? 0;
        String end = arrivalEnd;
        int threshold = SqlValue.asInt(rule['late_threshold_minutes']) ?? 0;

        // applyWeekdayOverride() — src/lib/attendance/day-overrides.ts.
        // Shift-derived rules (negative ids) carry their own schedule.
        if (id >= 0) {
          try {
            final Row? ov = await _db.queryOne(
              '''
              SELECT arrival_end_time, late_threshold_minutes
                FROM attendance_rule_day_overrides
               WHERE rule_id = ? AND weekday = ? LIMIT 1
              ''',
              <Object?>[id, weekdayOf(date)],
            );
            end = SqlValue.asString(ov?['arrival_end_time']) ?? end;
            threshold =
                SqlValue.asInt(ov?['late_threshold_minutes']) ?? threshold;
          } on Failure {
            // Overrides are an enhancement — never break evaluation.
          }
        }
        return addMinutesToTime(end, threshold);
      }
    } on Failure {
      // Fall through to the platform default.
    }
    return '08:45:00';
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/attendance/person-profiles?person_id= —
  // src/app/api/attendance/person-profiles/route.ts
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<PersonAttendance>> personProfile({
    required int personId,
    required String role,
    int days = 30,
  }) async {
    try {
      final String safeRole = role == 'student' ? 'student' : 'staff';
      final int window = days.clamp(14, 120);
      // The route derives `since` from a UTC date, not the school's — kept.
      final String since = DateTime.now()
          .toUtc()
          .subtract(Duration(days: window))
          .toIso8601String()
          .substring(0, 10);

      final List<Row> rows = await _db.query(
        '''
        SELECT attendance_date AS date, status FROM attendance_records
         WHERE school_id = ? AND person_id = ? AND role_type = ? AND attendance_date >= ?
         ORDER BY attendance_date ASC
        ''',
        <Object?>[_schoolId, personId, safeRole, since],
      );

      final List<PersonDay> series = rows
          .map(
            (Row r) => PersonDay(
              date: (SqlValue.asString(r['date']) ?? '').padRight(10).substring(0, 10),
              status: SqlValue.asString(r['status']) ?? '',
            ),
          )
          .toList(growable: false);

      return Ok<PersonAttendance>(
        PersonAttendance(
          personId: personId,
          role: safeRole,
          days: window,
          profile: profilePerson(series),
          series: series,
        ),
      );
    } on Failure catch (failure) {
      return Err<PersonAttendance>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/classes — src/app/api/classes/route.ts (id + name)
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<List<ClassOption>>> classes() async {
    try {
      final List<Row> rows = await _db.query(
        '''
        SELECT c.id, c.name FROM classes c
         WHERE c.school_id = ? AND c.deleted_at IS NULL
         ORDER BY c.class_level, c.name
        ''',
        <Object?>[_schoolId],
      );
      return Ok<List<ClassOption>>(
        rows
            .map(
              (Row r) => ClassOption(
                id: SqlValue.asInt(r['id']) ?? 0,
                name: SqlValue.asString(r['name']) ?? '',
              ),
            )
            .where((ClassOption c) => c.id > 0 && c.name.isNotEmpty)
            .toList(growable: false),
      );
    } on Failure catch (failure) {
      return Err<List<ClassOption>>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Trend and unmatched — the existing screens.
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<List<AttendanceTrendDay>>> trend({
    int days = 14,
    AttendanceAudience audience = AttendanceAudience.students,
  }) async {
    try {
      final StringBuffer where = StringBuffer(
        'r.school_id = ? '
        'AND r.attendance_date >= DATE_SUB(CURDATE(), INTERVAL $days DAY)',
      );
      final List<Object?> params = <Object?>[_schoolId];

      if (audience.isFiltered) {
        where.write(' AND r.role_type = ?');
        params.add(audience.wireValue);
      }

      final List<Row> rows = await _db.query('''
        SELECT r.attendance_date AS d,
               SUM(r.status = 'present')     AS present,
               SUM(r.status = 'late')        AS late,
               SUM(r.status = 'absent')      AS absent,
               SUM(r.status = 'half_day')    AS half_day,
               SUM(r.status IN ('weekend','holiday','early_leave')) AS other
          FROM attendance_records r
         WHERE $where
         GROUP BY r.attendance_date
         ORDER BY r.attendance_date DESC
         ${DraisDatabase.limitClause(limit: days + 5)}
        ''', params);

      return Ok<List<AttendanceTrendDay>>(
        rows
            .map(
              (Row row) => AttendanceTrendDay(
                date: SqlValue.asDate(row['d']) ?? DateTime.now(),
                present: SqlValue.asInt(row['present']) ?? 0,
                late: SqlValue.asInt(row['late']) ?? 0,
                absent: SqlValue.asInt(row['absent']) ?? 0,
                halfDay: SqlValue.asInt(row['half_day']) ?? 0,
                other: SqlValue.asInt(row['other']) ?? 0,
              ),
            )
            .toList(growable: false),
      );
    } on Failure catch (failure) {
      return Err<List<AttendanceTrendDay>>(failure);
    }
  }

  @override
  Future<Result<List<UnmatchedPunch>>> unmatchedPunches({
    int limit = 100,
  }) async {
    try {
      final int offset = (await _timePolicy()).offsetMinutes;
      // An unmatched event has no person to join through, which is exactly
      // why the scope must come from the event's own `school_id`.
      final List<Row> rows = await _db.query(
        '''
        SELECT e.id, e.punch_at, e.display_name, e.source, e.resolution_path
          FROM attendance_raw_events e
         WHERE e.school_id = ?
           AND e.matched = 0
           AND e.punch_at >= DATE_SUB(UTC_TIMESTAMP(), INTERVAL 90 DAY)
         ORDER BY e.punch_at DESC
         ${DraisDatabase.limitClause(limit: limit)}
        ''',
        <Object?>[_schoolId],
      );

      return Ok<List<UnmatchedPunch>>(
        rows
            .map(
              (Row row) => UnmatchedPunch(
                id: SqlValue.asInt(row['id']) ?? 0,
                // Shown as school wall time: punch_at is a UTC instant.
                punchAt: schoolWallTime(
                  SqlValue.asUtcInstant(row['punch_at']) ??
                      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
                  offsetMinutes: offset,
                ),
                source: SqlValue.asString(row['source']) ?? 'unknown',
                displayName: SqlValue.asString(row['display_name']),
                resolutionPath: SqlValue.asString(row['resolution_path']),
              ),
            )
            .toList(growable: false),
      );
    } on Failure catch (failure) {
      return Err<List<UnmatchedPunch>>(failure);
    }
  }
}
