import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/database/longterm/modules.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/storage/cache_store.dart';
import 'package:drais/features/timetable/domain/timetable.dart';

/// The timetable, straight from TiDB — `/api/timetable-metadata` and
/// `/api/timetable-entries` (DRAIS LongTerm), in Dart.
///
/// ## Cached for offline use
///
/// The first module to use `docs/OFFLINE_STRATEGY.md` step 1: a timetable
/// changes rarely and is wanted constantly, often where signal is poor. Each
/// successful load stores the server's answer (rows, never anything derived)
/// in [CacheStore], keyed by school and selection. When the database cannot
/// be reached, the last stored copy is served and marked as such. The cache
/// is cleared on sign-in and sign-out by the auth repository, as for every
/// cached read.
class TimetableDirectRepository implements TimetableRepository {
  /// Creates the repository.
  TimetableDirectRepository({
    required DraisDatabase database,
    required int schoolId,
    required int userId,
    required CacheStore cache,
  }) : _db = database,
       _schoolId = schoolId,
       _userId = userId,
       _cache = cache;

  final DraisDatabase _db;
  final int _schoolId;
  final int _userId;
  final CacheStore _cache;

  /// Long: a timetable is set per term. Staleness is shown, not hidden.
  static const Duration _ttl = Duration(days: 7);

  String _key(int? classId, int? streamId, int? teacherId) =>
      'direct://timetable/$_schoolId?class=${classId ?? ''}'
      '&stream=${streamId ?? ''}&teacher=${teacherId ?? ''}';

  @override
  Future<Result<TimetableView>> load({
    int? classId,
    int? streamId,
    int? teacherId,
  }) async {
    final String key = _key(classId, streamId, teacherId);
    try {
      final Failure? off = await checkModule(_db, _schoolId, 'academics');
      if (off != null) return Err<TimetableView>(off);

      final List<Object?> school = <Object?>[_schoolId];
      final List<Object?> entryParams = <Object?>[_schoolId];
      final StringBuffer filters = StringBuffer();
      if (classId != null) {
        filters.write(' AND te.class_id = ?');
        entryParams.add(classId);
      }
      if (streamId != null) {
        filters.write(' AND te.stream_id = ?');
        entryParams.add(streamId);
      }
      if (teacherId != null) {
        filters.write(' AND te.teacher_id = ?');
        entryParams.add(teacherId);
      }

      // The metadata route also returns subjects and teachers, for the
      // web's edit form; this view is read-only and does not fetch them.
      final List<List<Row>> r = await Future.wait(<Future<List<Row>>>[
        _db.query(
          'SELECT id, name, class_level FROM classes WHERE school_id = ? ORDER BY class_level, name',
          school,
        ),
        _db.query(
          'SELECT id, name, class_id FROM streams WHERE school_id = ? ORDER BY name',
          school,
        ),
        _db.query(
          'SELECT id, name, short_name, CAST(start_time AS CHAR) AS start_time, '
          'CAST(end_time AS CHAR) AS end_time, period_order, is_break '
          'FROM timetable_periods WHERE school_id = ? ORDER BY period_order',
          school,
        ),
        // No lessons are fetched without a selection — the web grid fetches
        // entries only once a class is chosen.
        if (classId != null || teacherId != null)
          _db.query('''
            SELECT te.id, te.day_of_week, te.period_id, te.class_id, te.stream_id,
                   te.subject_id, te.teacher_id, te.room,
                   c.name AS class_name, st.name AS stream_name,
                   sub.name AS subject_name, sub.code AS subject_code,
                   COALESCE(CONCAT(p.first_name, ' ', p.last_name), CONCAT('Staff ', stf.id)) AS teacher_name
              FROM timetable_entries te
              JOIN timetable_periods tp ON te.period_id = tp.id
              JOIN classes c ON te.class_id = c.id
              JOIN subjects sub ON te.subject_id = sub.id
              LEFT JOIN streams st ON te.stream_id = st.id
              LEFT JOIN staff stf ON te.teacher_id = stf.id
              LEFT JOIN people p ON stf.person_id = p.id
             WHERE te.school_id = ?$filters
             ORDER BY te.day_of_week, tp.period_order
            ''', entryParams)
        else
          Future<List<Row>>.value(const <Row>[]),
      ]);

      final Map<String, Object?> body = <String, Object?>{
        'classes': r[0].map(_jsonRow).toList(),
        'streams': r[1].map(_jsonRow).toList(),
        'periods': r[2].map(_jsonRow).toList(),
        'entries': r[3].map(_jsonRow).toList(),
      };
      await _cache.write(key, body, ttl: _ttl);
      return Ok<TimetableView>(_view(body));
    } on NetworkFailure catch (failure) {
      final CachedEntry? cached = _cache.read(key);
      final Object? body = cached?.body;
      if (body is Map) {
        return Ok<TimetableView>(
          _view(
            body.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v)),
            cachedAt: cached!.storedAt,
          ),
        );
      }
      return Err<TimetableView>(failure);
    } on Failure catch (failure) {
      return Err<TimetableView>(failure);
    }
  }

  /// Row values made JSON-safe for the cache.
  static Map<String, Object?> _jsonRow(Row row) => row.map(
    (String k, Object? v) => MapEntry<String, Object?>(
      k,
      v == null || v is num || v is bool || v is String ? v : '$v',
    ),
  );

  static List<Map<String, Object?>> _list(Object? v) => v is List
      ? v
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> m) =>
                  m.map((Object? k, Object? x) => MapEntry<String, Object?>('$k', x)),
            )
            .toList()
      : const <Map<String, Object?>>[];

  static TimetableView _view(Map<String, Object?> b, {DateTime? cachedAt}) {
    String? s(Map<String, Object?> r, String k) {
      final String? v = SqlValue.asString(r[k]);
      return (v == null || v.isEmpty) ? null : v;
    }

    return TimetableView(
      cachedAt: cachedAt,
      metadata: TimetableMetadata(
        classes: <TimetableOption>[
          for (final Map<String, Object?> c in _list(b['classes']))
            TimetableOption(id: SqlValue.asInt(c['id']) ?? 0, label: s(c, 'name') ?? ''),
        ],
        streams: <TimetableOption>[
          for (final Map<String, Object?> st in _list(b['streams']))
            TimetableOption(
              id: SqlValue.asInt(st['id']) ?? 0,
              label: s(st, 'name') ?? '',
              parentId: SqlValue.asInt(st['class_id']),
            ),
        ],
        periods: <TimetablePeriod>[
          for (final Map<String, Object?> p in _list(b['periods']))
            TimetablePeriod(
              id: SqlValue.asInt(p['id']) ?? 0,
              name: s(p, 'name') ?? '',
              shortName: s(p, 'short_name'),
              startTime: s(p, 'start_time'),
              endTime: s(p, 'end_time'),
              order: SqlValue.asInt(p['period_order']) ?? 0,
              isBreak: SqlValue.asBool(p['is_break']),
            ),
        ],
      ),
      entries: <TimetableEntry>[
        for (final Map<String, Object?> e in _list(b['entries']))
          TimetableEntry(
            id: SqlValue.asInt(e['id']) ?? 0,
            dayOfWeek: SqlValue.asInt(e['day_of_week']) ?? 0,
            periodId: SqlValue.asInt(e['period_id']) ?? 0,
            classId: SqlValue.asInt(e['class_id']) ?? 0,
            streamId: SqlValue.asInt(e['stream_id']),
            subjectId: SqlValue.asInt(e['subject_id']) ?? 0,
            teacherId: SqlValue.asInt(e['teacher_id']),
            room: s(e, 'room'),
            className: s(e, 'class_name'),
            streamName: s(e, 'stream_name'),
            subjectName: s(e, 'subject_name'),
            subjectCode: s(e, 'subject_code'),
            teacherName: s(e, 'teacher_name'),
          ),
      ],
    );
  }

  @override
  Future<Result<int?>> myStaffId() async {
    try {
      final Row? r = await _db.queryOne(
        '''
        SELECT stf.id FROM users u
          JOIN staff stf ON stf.person_id = u.person_id
                        AND stf.school_id = ? AND stf.deleted_at IS NULL
         WHERE u.id = ? LIMIT 1
        ''',
        <Object?>[_schoolId, _userId],
      );
      return Ok<int?>(SqlValue.asInt(r?['id']));
    } on Failure catch (failure) {
      return Err<int?>(failure);
    }
  }
}
