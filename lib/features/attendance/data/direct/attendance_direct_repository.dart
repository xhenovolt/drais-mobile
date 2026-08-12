import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/features/attendance/domain/entities/attendance_log_entry.dart';
import 'package:drais/features/attendance/domain/repositories/attendance_repository.dart';

/// Reads attendance straight from TiDB, for direct mode.
///
/// ## Tenant scope is the whole game here
///
/// There is no server applying `getSessionSchoolId()`, so **every query below
/// takes `schoolId` from the validated session and filters on it**. Not from a
/// screen, not from a dropdown, not from a cached value the UI happens to
/// hold. That discipline is the only thing standing between this mode and one
/// school reading another's register.
///
/// `attendance_raw_events` carries its own `school_id`, and every query here
/// filters on it — the same column `src/lib/attendance/health.ts` and the rest
/// of the platform scope by. It is the only scope that works for an *unmatched*
/// punch, which by definition has no person to join through.
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

  @override
  Future<Result<List<AttendanceLogEntry>>> logEntries(
    AttendanceLogQuery query,
  ) async {
    try {
      final StringBuffer where = StringBuffer(
        // Scope by school, and by the school-local day.
        'e.school_id = ? AND DATE(e.punch_at) = ?',
      );
      final List<Object?> params = <Object?>[_schoolId, query.date];

      if (query.audience.isFiltered) {
        where.write(' AND e.role_type = ?');
        params.add(query.audience.wireValue);
      }

      final String? search = query.search?.trim();
      if (search != null && search.isNotEmpty) {
        where.write(' AND LOWER(e.display_name) LIKE ?');
        params.add('%${search.toLowerCase()}%');
      }

      if (query.onlyNeedingAttention) {
        where.write(
          ' AND (e.matched = 0 OR e.is_provisional = 1 '
          "OR LOWER(COALESCE(e.time_confidence, '')) = 'low')",
        );
      }

      final List<Row> rows = await _db.query('''
        SELECT e.id, e.person_id, e.role_type, e.punch_at, e.source,
               e.matched, e.display_name, e.resolution_path, e.resolution_score,
               e.io_mode, e.derived_event,
               e.device_reported_time, e.clock_skew_seconds,
               e.time_confidence, e.is_provisional, e.provisional_reason
          FROM attendance_raw_events e
         WHERE $where
         ORDER BY e.punch_at DESC, e.id DESC
         ${DraisDatabase.limitClause(limit: query.limit, offset: query.offset)}
        ''', params);

      _logger.debug(
        'Loaded attendance log.',
        context: <String, Object?>{
          'date': query.date,
          'rows': rows.length,
          'audience': query.audience.wireValue,
        },
      );

      return Ok<List<AttendanceLogEntry>>(
        rows.map(_toEntry).toList(growable: false),
      );
    } on Failure catch (failure) {
      return Err<List<AttendanceLogEntry>>(failure);
    }
  }

  @override
  Future<Result<AttendanceDaySummary>> daySummary({
    required String date,
    AttendanceAudience audience = AttendanceAudience.all,
  }) async {
    try {
      // Verdicts come from attendance_records — the engine's output. Counting
      // raw punches instead would double-count anyone who punched in and out.
      final StringBuffer verdictWhere = StringBuffer(
        'r.school_id = ? AND r.attendance_date = ?',
      );
      final List<Object?> verdictParams = <Object?>[_schoolId, date];

      if (audience.isFiltered) {
        verdictWhere.write(' AND r.role_type = ?');
        verdictParams.add(audience.wireValue);
      }

      final List<Row> verdicts = await _db.query(
        'SELECT r.status, COUNT(*) AS n FROM attendance_records r '
        'WHERE $verdictWhere GROUP BY r.status',
        verdictParams,
      );

      int present = 0;
      int late = 0;
      int absent = 0;
      int halfDay = 0;
      int other = 0;

      for (final Row row in verdicts) {
        final int n = SqlValue.asInt(row['n']) ?? 0;
        switch (SqlValue.asString(row['status'])) {
          case 'present':
            present += n;
          case 'late':
            late += n;
          case 'absent':
            absent += n;
          case 'half_day':
            halfDay += n;
          default:
            other += n;
        }
      }

      // Punch volume is a separate question from verdicts, and worth showing:
      // zero punches on a school day means the devices are not reporting,
      // which no verdict count would reveal.
      final Row? punches = await _db.queryOne(
        '''
        SELECT COUNT(*) AS total,
               SUM(CASE WHEN e.matched = 0 THEN 1 ELSE 0 END) AS unmatched
          FROM attendance_raw_events e
         WHERE e.school_id = ? AND DATE(e.punch_at) = ?
        ''',
        <Object?>[_schoolId, date],
      );

      return Ok<AttendanceDaySummary>(
        AttendanceDaySummary(
          present: present,
          late: late,
          absent: absent,
          halfDay: halfDay,
          other: other,
          punches: SqlValue.asInt(punches?['total']) ?? 0,
          unmatchedPunches: SqlValue.asInt(punches?['unmatched']) ?? 0,
        ),
      );
    } on Failure catch (failure) {
      return Err<AttendanceDaySummary>(failure);
    }
  }

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
      // An unmatched event has no person to join through, which is exactly
      // why the scope must come from the event's own `school_id`. Omitting it
      // here would list every school's unidentified punches.
      final List<Row> rows = await _db.query(
        '''
        SELECT e.id, e.punch_at, e.display_name, e.source, e.resolution_path
          FROM attendance_raw_events e
         WHERE e.school_id = ?
           AND e.matched = 0
           AND e.punch_at >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
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
                punchAt: SqlValue.asDate(row['punch_at']) ?? DateTime.now(),
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

  AttendanceLogEntry _toEntry(Row row) => AttendanceLogEntry(
    id: SqlValue.asInt(row['id']) ?? 0,
    // punch_at is NOT NULL in the schema; the fallback exists so one bad
    // row cannot take down the whole screen.
    punchAt: SqlValue.asDate(row['punch_at']) ?? DateTime.now(),
    source: PunchSource.fromWire(SqlValue.asString(row['source'])),
    roleType: SqlValue.asString(row['role_type']) ?? 'student',
    matched: SqlValue.asBool(row['matched']),
    personId: SqlValue.asInt(row['person_id']),
    displayName: SqlValue.asString(row['display_name']),
    deviceReportedTime: SqlValue.asDate(row['device_reported_time']),
    clockSkewSeconds: SqlValue.asInt(row['clock_skew_seconds']),
    timeConfidence: TimeConfidence.fromWire(
      SqlValue.asString(row['time_confidence']),
    ),
    resolutionPath: SqlValue.asString(row['resolution_path']),
    resolutionScore: double.tryParse(
      SqlValue.asString(row['resolution_score']) ?? '',
    ),
    ioMode: SqlValue.asInt(row['io_mode']),
    derivedEvent: SqlValue.asString(row['derived_event']),
    isProvisional: SqlValue.asBool(row['is_provisional']),
    provisionalReason: SqlValue.asString(row['provisional_reason']),
  );
}
