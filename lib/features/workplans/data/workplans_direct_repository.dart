import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/database/longterm/modules.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/workplans/domain/workplans.dart';

/// Work plans, straight from TiDB — `src/app/api/work-plans/route.ts` (DRAIS
/// LongTerm), the route the web navigation's `/work-plans` page uses. The
/// older `/api/workplans` serves a separate legacy component and is not
/// ported.
///
/// ## One deliberate correction (security)
///
/// The route's `PATCH` and `DELETE` check **no session and no school**: any
/// caller can edit or delete any school's plan by id. [update] runs as the
/// signed-in school and adds `school_id = ?` and the module gate. Delete is
/// not ported — the web page offers no delete.
class WorkPlansDirectRepository implements WorkPlansRepository {
  /// Creates the repository.
  WorkPlansDirectRepository({
    required DraisDatabase database,
    required int schoolId,
  }) : _db = database,
       _schoolId = schoolId;

  final DraisDatabase _db;
  final int _schoolId;

  Future<Failure?> _gate() => checkModule(_db, _schoolId, 'work_plans');

  @override
  Future<Result<List<WorkPlan>>> list({
    WorkPlanStatus? status,
    WorkPlanPriority? priority,
  }) async {
    try {
      final Failure? off = await _gate();
      if (off != null) return Err<List<WorkPlan>>(off);

      final List<Object?> params = <Object?>[_schoolId];
      final StringBuffer where = StringBuffer(
        "w.school_id = ? AND (w.deleted_at IS NULL OR w.deleted_at = '')",
      );
      if (status != null) {
        where.write(' AND w.status = ?');
        params.add(status.wireValue);
      }
      if (priority != null) {
        where.write(' AND w.priority = ?');
        params.add(priority.wireValue);
      }
      final List<Row> rows = await _db.query('''
        SELECT w.id, w.title, w.description, w.owner_type, w.owner_id,
               CAST(w.start_datetime AS CHAR) AS start_datetime,
               CAST(w.end_datetime AS CHAR) AS end_datetime,
               w.status, w.priority, w.progress, w.assigned_to,
               CAST(w.created_at AS CHAR) AS created_at,
               CONCAT(p.first_name, ' ', p.last_name) AS assignee_name,
               d.name AS department_name
          FROM workplans w
          LEFT JOIN staff s ON w.assigned_to = s.id
          LEFT JOIN people p ON s.person_id = p.id
          LEFT JOIN departments d ON w.owner_type = 'department' AND w.owner_id = d.id
         WHERE $where
         ORDER BY w.created_at DESC
        ''', params);

      String? v(Row r, String k) {
        final String? x = SqlValue.asString(r[k]);
        return (x == null || x.isEmpty) ? null : x;
      }

      return Ok<List<WorkPlan>>(
        rows
            .map(
              (Row r) => WorkPlan(
                id: SqlValue.asInt(r['id']) ?? 0,
                title: v(r, 'title') ?? '',
                description: v(r, 'description'),
                ownerType: v(r, 'owner_type'),
                startDatetime: v(r, 'start_datetime'),
                endDatetime: v(r, 'end_datetime'),
                status: WorkPlanStatus.fromWire(v(r, 'status')),
                priority: WorkPlanPriority.fromWire(v(r, 'priority')),
                progress: SqlValue.asInt(r['progress']) ?? 0,
                assignedTo: SqlValue.asInt(r['assigned_to']),
                assigneeName: v(r, 'assignee_name'),
                departmentName: v(r, 'department_name'),
                createdAt: v(r, 'created_at'),
              ),
            )
            .toList(growable: false),
      );
    } on Failure catch (failure) {
      return Err<List<WorkPlan>>(failure);
    }
  }

  @override
  Future<Result<int>> create({
    required String title,
    String? description,
    WorkPlanPriority priority = WorkPlanPriority.medium,
    String? startDatetime,
    String? endDatetime,
  }) async {
    try {
      if (title.trim().isEmpty) {
        return const Err<int>(ValidationFailure(message: 'Work plan title is required'));
      }
      final Failure? off = await _gate();
      if (off != null) return Err<int>(off);

      // The web form sends no owner_id or assigned_to; they are written as
      // NULL here (mysql2 would reject the route's undefined — PARITY §4.7).
      final int? id = await _db.insert(
        '''
        INSERT INTO workplans (
          school_id, title, description, owner_type, owner_id,
          start_datetime, end_datetime, priority, assigned_to
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          _schoolId,
          title.trim(),
          description,
          'school',
          null,
          startDatetime,
          endDatetime,
          priority.wireValue,
          null,
        ],
      );
      return Ok<int>(id ?? 0);
    } on Failure catch (failure) {
      return Err<int>(failure);
    }
  }

  @override
  Future<Result<void>> update(WorkPlan plan) async {
    try {
      final Failure? off = await _gate();
      if (off != null) return Err<void>(off);
      // Existence first: MySQL reports *changed* rows, so an UPDATE that
      // writes identical values would otherwise read as "not found".
      final Row? exists = await _db.queryOne(
        'SELECT id FROM workplans WHERE id = ? AND school_id = ? LIMIT 1',
        <Object?>[plan.id, _schoolId],
      );
      if (exists == null) {
        return const Err<void>(NotFoundFailure(message: 'Work plan not found'));
      }
      await _db.execute(
        '''
        UPDATE workplans
           SET title = ?, description = ?, start_datetime = ?, end_datetime = ?,
               status = ?, priority = ?, progress = ?, assigned_to = ?,
               updated_at = CURRENT_TIMESTAMP
         WHERE id = ? AND school_id = ?
        ''',
        <Object?>[
          plan.title,
          plan.description,
          plan.startDatetime,
          plan.endDatetime,
          plan.status.wireValue,
          plan.priority.wireValue,
          plan.progress.clamp(0, 100),
          plan.assignedTo,
          plan.id,
          _schoolId,
        ],
      );
      return const Ok<void>(null);
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }
}
