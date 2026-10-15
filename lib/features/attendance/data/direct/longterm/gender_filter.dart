/// Gender filtering over dirty free-text data.
///
/// **Ported from `src/lib/attendance/gender.ts`** (DRAIS LongTerm).
/// `people.gender` holds 'male', 'Male', 'M', 'female', 'Female', 'F' and
/// blanks side by side in production; an exact match silently misses most
/// real rows. Normalised at read time only — stored data is never rewritten.
library;

const Map<String, List<String>> _variants = <String, List<String>>{
  'male': <String>['male', 'm'],
  'female': <String>['female', 'f'],
};

/// Whether [value] is a supported filter — `isGenderFilter()`.
bool isGenderFilter(String? value) => value == 'male' || value == 'female';

/// A SQL condition matching every stored variant — `genderMatchSql()`.
/// Never matches NULL or blank.
({String sql, List<String> params}) genderMatchSql(
  String column,
  String value,
) {
  final List<String> v = _variants[value]!;
  return (
    sql: 'LOWER(TRIM($column)) IN (${List<String>.filled(v.length, '?').join(',')})',
    params: List<String>.of(v),
  );
}
