/// `getCurrentTerm()` from `src/lib/terms.ts` (DRAIS LongTerm).
///
/// The platform's three-step priority — date-matched active term, then any
/// active term, then the latest term — in one ordered statement: sorting by
/// the two priority flags and then start date returns the row the three
/// queries would. `today` is a UTC date, as the platform computes it.
///
/// Note this is **not** `resolveTermContext()`, which the enrol form uses and
/// which never falls back to a stale term. The list pages and bulk
/// promotion use this one; the two can disagree between terms.
library;

import 'package:drais/core/database/drais_database.dart';

/// The current term's id and name, or null when the school has none.
Future<({int id, String name})?> currentTerm(
  DraisDatabase db,
  int schoolId,
) async {
  final String today = DateTime.now().toUtc().toIso8601String().substring(
    0,
    10,
  );
  final Row? row = await db.queryOne(
    '''
    SELECT t.id, t.name
      FROM terms t
      JOIN academic_years ay ON t.academic_year_id = ay.id
     WHERE t.school_id = ? AND t.deleted_at IS NULL
     ORDER BY (t.status = 'active' AND t.start_date <= ? AND t.end_date >= ?) DESC,
              (t.status = 'active') DESC,
              t.start_date DESC
     LIMIT 1
    ''',
    <Object?>[schoolId, today, today],
  );
  final int? id = SqlValue.asInt(row?['id']);
  return id == null ? null : (id: id, name: SqlValue.asString(row!['name']) ?? '');
}
