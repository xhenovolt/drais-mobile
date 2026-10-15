import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/domain/entities/student_admin.dart';
import 'package:drais/features/students/domain/entities/students.dart';

/// Contacts, duplicates and bulk enrolment.
///
/// | Method | LongTerm source |
/// |---|---|
/// | [contacts] | `GET /api/students/contacts` |
/// | [addContact] | `POST /api/students/contacts` (JSON quick-add; not the Excel import) |
/// | [updateContact] / [removeContact] | `PUT` / `DELETE /api/students/contacts/[id]` |
/// | [setPrimaryContact] | `POST /api/students/[id]/primary-contact` |
/// | [duplicates] | `GET /api/students/duplicates` |
/// | [merge] | `POST /api/students/duplicates/merge` |
/// | [promoteClass] | `POST /api/enrollments/bulk` `mode: promote` |
/// | [enrollMany] | `POST /api/enrollments/bulk` `mode: multiple_students` |
abstract interface class StudentAdminRepository {
  /// Contacts across the school, or one learner's when [studentId] is given.
  Future<Result<ContactPage>> contacts({
    int? studentId,
    String? search,
    int page = 1,
    int limit = 50,
  });

  /// Adds a contact to a learner, linking an existing one with the same
  /// phone or email instead of duplicating it.
  Future<Result<String>> addContact(int studentId, ContactInput input);

  /// Edits a contact.
  Future<Result<void>> updateContact(int contactId, ContactInput input);

  /// Removes a contact from every learner and soft-deletes it.
  Future<Result<void>> removeContact(int contactId);

  /// Creates or updates the learner's primary contact by phone.
  Future<Result<String>> setPrimaryContact(
    int studentId, {
    required String phone,
    String firstName = '',
    String lastName = '',
    String relationship = 'Guardian',
  });

  /// Potential duplicate groups.
  Future<Result<DuplicateReport>> duplicates({int limit = 200});

  /// Merges each secondary into its primary, one transaction per group.
  Future<Result<List<MergeOutcome>>> merge(
    List<({int primaryId, List<int> secondaryIds})> groups,
  );

  /// Moves a whole class (or [studentIds]) up to [toClassId].
  /// Returns how many learners were promoted.
  Future<Result<int>> promoteClass({
    required int fromClassId,
    required int toClassId,
    required int academicYearId,
    int? termId,
    List<int> studentIds = const <int>[],
  });

  /// Enrols several learners with the same class, term and program.
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
  });
}
