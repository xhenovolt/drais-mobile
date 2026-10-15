/// Duplicate grouping and contact matching.
///
/// Ported from DRAIS LongTerm:
///
/// * [buildDuplicateGroups] — the grouping, confidence and "already captured"
///   rules of `GET /api/students/duplicates`
///   (`src/app/api/students/duplicates/route.ts`);
/// * [normalizePhone] / [normalizeEmail] — `src/lib/contacts/import.ts`.
///
/// The route fetches each group's members with its own query; the caller
/// here fetches every member in one statement and hands the rows over
/// already keyed. The grouping itself is unchanged.
library;

import 'package:drais/features/students/domain/entities/student_admin.dart';

/// `normalizePhone()` — whitespace, brackets, dots and dashes removed,
/// lowercased.
String normalizePhone(String? value) =>
    (value ?? '').trim().replaceAll(RegExp(r'[\s().-]'), '').toLowerCase();

/// `normalizeEmail()`.
String normalizeEmail(String? value) => (value ?? '').trim().toLowerCase();

bool _pairShares(
  List<DuplicateMember> s,
  Object? Function(DuplicateMember m) field,
) {
  for (int i = 0; i < s.length; i++) {
    for (int j = 0; j < s.length; j++) {
      if (i == j) continue;
      final Object? a = field(s[i]);
      final Object? b = field(s[j]);
      // The route's truthiness test: null and '' never match.
      if (a != null && a != '' && b != null && b != '' && a == b) return true;
    }
  }
  return false;
}

/// Builds the route's groups.
///
/// [nameKeys] are the exact-name groups in the route's order (largest
/// first); [membersByName] maps each to its members, oldest first.
/// [admissionNos] and [membersByAdmission] are the same for shared
/// admission numbers.
List<DuplicateGroup> buildDuplicateGroups({
  required List<String> nameKeys,
  required Map<String, List<DuplicateMember>> membersByName,
  required List<String> admissionNos,
  required Map<String, List<DuplicateMember>> membersByAdmission,
}) {
  final List<DuplicateGroup> groups = <DuplicateGroup>[];
  int groupId = 0;

  for (final String key in nameKeys) {
    final List<DuplicateMember> students =
        membersByName[key] ?? const <DuplicateMember>[];
    if (students.length <= 1) continue;
    groupId++;

    String confidence = 'medium';
    String matchReason = 'Exact name match';
    if (_pairShares(students, (DuplicateMember m) => m.admissionNo)) {
      confidence = 'high';
      matchReason = 'Same name + same admission number';
    } else if (_pairShares(students, (DuplicateMember m) => m.classId)) {
      confidence = 'high';
      matchReason = 'Same name + same class';
    }
    groups.add(
      DuplicateGroup(
        groupId: groupId,
        matchReason: matchReason,
        confidence: confidence,
        students: students,
      ),
    );
  }

  for (final String adm in admissionNos) {
    // Skip when a name group already holds two or more with this number.
    final bool alreadyCaptured = groups.any(
      (DuplicateGroup g) =>
          g.students.where((DuplicateMember s) => s.admissionNo == adm).length >
          1,
    );
    if (alreadyCaptured) continue;

    final List<DuplicateMember> students =
        membersByAdmission[adm] ?? const <DuplicateMember>[];
    if (students.length <= 1) continue;
    groupId++;
    groups.add(
      DuplicateGroup(
        groupId: groupId,
        matchReason: 'Same admission number',
        confidence: 'high',
        students: students,
      ),
    );
  }
  return groups;
}
