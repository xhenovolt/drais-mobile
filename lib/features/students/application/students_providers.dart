import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/domain/entities/student_admin.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/features/students/domain/repositories/students_repository.dart';

/// Which list the Students screen shows — the web list page's two tabs.
enum StudentsTab {
  /// `/api/students/enrolled`: this term's learners.
  enrolled('Enrolled'),

  /// `/api/students/admitted`: admitted, not enrolled this term.
  admitted('Admitted');

  const StudentsTab(this.label);

  /// Tab label.
  final String label;
}

T _unwrap<T>(Result<T> result) => result.fold(
  onOk: (T value) => value,
  onErr: (Failure failure) => throw failure,
);

/// One tab of the roster.
final AutoDisposeFutureProviderFamily<
  StudentListResult,
  ({StudentsTab tab, String? search, int? classId})
>
studentListProvider = FutureProvider.autoDispose
    .family<
      StudentListResult,
      ({StudentsTab tab, String? search, int? classId})
    >((Ref ref, ({StudentsTab tab, String? search, int? classId}) q) async {
      final StudentsRepository repo = ref.watch(studentsRepositoryProvider);
      return _unwrap(switch (q.tab) {
        StudentsTab.enrolled => await repo.enrolled(
          search: q.search,
          classId: q.classId,
        ),
        StudentsTab.admitted => await repo.admitted(search: q.search),
      });
    });

/// A learner's profile.
final AutoDisposeFutureProviderFamily<StudentProfile, int>
studentProfileProvider = FutureProvider.autoDispose
    .family<StudentProfile, int>(
      (Ref ref, int id) async =>
          _unwrap(await ref.watch(studentsRepositoryProvider).profile(id)),
    );

/// A learner's most recent enrolment, for the enrol form.
final AutoDisposeFutureProviderFamily<EnrollmentRecord?, int>
previousEnrollmentProvider = FutureProvider.autoDispose
    .family<EnrollmentRecord?, int>(
      (Ref ref, int id) async => _unwrap(
        await ref.watch(studentsRepositoryProvider).previousEnrollment(id),
      ),
    );

/// The school's contacts, first [limit] matching [search].
final AutoDisposeFutureProviderFamily<
  ContactPage,
  ({String? search, int limit})
>
contactsProvider = FutureProvider.autoDispose
    .family<ContactPage, ({String? search, int limit})>(
      (Ref ref, ({String? search, int limit}) q) async => _unwrap(
        await ref
            .watch(studentAdminRepositoryProvider)
            .contacts(search: q.search, limit: q.limit),
      ),
    );

/// Potential duplicate learners.
final AutoDisposeFutureProvider<DuplicateReport> duplicatesProvider =
    FutureProvider.autoDispose<DuplicateReport>(
      (Ref ref) async =>
          _unwrap(await ref.watch(studentAdminRepositoryProvider).duplicates()),
    );

/// Learners in Trash.
final AutoDisposeFutureProviderFamily<List<TrashedStudent>, String?>
studentTrashProvider = FutureProvider.autoDispose
    .family<List<TrashedStudent>, String?>(
      (Ref ref, String? search) async => _unwrap(
        await ref.watch(studentsRepositoryProvider).trash(search: search),
      ),
    );

/// Everything the enrol form offers.
final AutoDisposeFutureProvider<EnrollmentOptions> enrollmentOptionsProvider =
    FutureProvider.autoDispose<EnrollmentOptions>(
      (Ref ref) async =>
          _unwrap(await ref.watch(studentsRepositoryProvider).enrollmentOptions()),
    );
