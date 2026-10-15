import 'package:drais/features/students/domain/entities/students.dart';

/// The class the web enrol form pre-selects for a decision.
///
/// **Ported from the class-suggestion effect in
/// `src/app/students/enroll/page.tsx`** (DRAIS LongTerm): continue → the same
/// class; promote → the class one `class_level` up; demote → one down;
/// first time → no suggestion. A suggestion only; the person enrolling
/// chooses.
int? suggestClassId(
  EnrollmentDecision decision,
  EnrollmentRecord? previous,
  List<Choice> classes,
) {
  if (previous == null) return null;
  switch (decision) {
    case EnrollmentDecision.continueSame:
      return previous.classId;
    case EnrollmentDecision.promote:
    case EnrollmentDecision.demote:
      // `(class_level ?? -99) === (prev.class_level ?? -99) ± 1`.
      final int target =
          (previous.classLevel ?? -99) +
          (decision == EnrollmentDecision.promote ? 1 : -1);
      for (final Choice c in classes) {
        if ((c.level ?? -99) == target) return c.id;
      }
      return null;
    case EnrollmentDecision.firstTime:
      return null;
  }
}
