import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/domain/entities/students.dart';

/// Learners, as DRAIS LongTerm's student routes serve them.
///
/// | Method | LongTerm source |
/// |---|---|
/// | [enrolled] | `GET /api/students/enrolled` |
/// | [admitted] | `GET /api/students/admitted` |
/// | [profile] | `GET /api/students/[id]/profile` |
/// | [previousEnrollment] | `GET /api/students/[id]/previous-enrollment` |
/// | [enrollmentOptions] | `/api/terms/current`, `/api/classes`, `/api/streams`, `/api/study-modes`, `/api/curriculums`, `/api/programs` |
/// | [admit] | `POST /api/students` |
/// | [enroll] | `POST /api/enrollments` |
abstract interface class StudentsRepository {
  /// Learners enrolled in a term — the current one unless [termId] is given.
  Future<Result<StudentListResult>> enrolled({
    int? termId,
    int? classId,
    String? search,
    String? status,
  });

  /// Learners admitted but not actively enrolled in the current term.
  Future<Result<StudentListResult>> admitted({String? search});

  /// One learner's full profile.
  Future<Result<StudentProfile>> profile(int studentId);

  /// The learner's most recent enrolment, or null for a first enrolment.
  Future<Result<EnrollmentRecord?>> previousEnrollment(int studentId);

  /// Everything the enrol form offers.
  Future<Result<EnrollmentOptions>> enrollmentOptions();

  /// Admits a learner. Returns the new ids.
  Future<Result<AdmissionResult>> admit(AdmissionRequest request);

  /// Enrols a learner. Returns the route's message, e.g. "Amina enrolled in P4".
  Future<Result<String>> enroll(EnrollmentRequest request);

  /// `PUT /api/students/edit` — personal fields.
  Future<Result<void>> update(int studentId, StudentEdit edit);

  /// `POST /api/students/bulk/status` — the route the web list page uses,
  /// with one id. [reason] is required for [StudentStatus.left].
  Future<Result<String>> setStatus(
    int studentId,
    StudentStatus status, {
    String? reason,
  });

  /// `PATCH /api/students/[id]/residency` — `day` or `boarding`.
  /// Requires `academics.residency.manage`.
  Future<Result<void>> setResidency(int studentId, String residency);

  /// `DELETE /api/students/delete` — archive to Trash (`archiveEntity`).
  Future<Result<void>> archive(int studentId, {String? reason});

  /// `GET /api/students/list?view=trash`.
  Future<Result<List<TrashedStudent>>> trash({String? search});

  /// `POST /api/students/restore`. Returns the number restored.
  Future<Result<int>> restore(List<int> studentIds);

  /// `POST /api/students/[id]/next-of-kin` — replaces the whole list.
  /// Requires `learners.profile.update`.
  Future<Result<void>> saveNextOfKin(int studentId, List<NextOfKinEntry> items);

  /// `PUT /api/students/[id]/profile` — all three blocks.
  /// Requires `learners.profile.update`.
  Future<Result<void>> saveProfileBlocks(int studentId, ProfileBlocks blocks);
}
