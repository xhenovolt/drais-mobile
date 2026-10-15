/// Contacts, duplicates and bulk enrolment — the rest of the Students module,
/// as LongTerm's routes shape them.
library;

/// One student–contact link — a row of `GET /api/students/contacts`.
class ContactRow {
  /// Creates a row.
  const ContactRow({
    required this.studentId,
    required this.contactId,
    this.relationship,
    this.isPrimary = false,
    this.contactType,
    this.occupation,
    this.aliveStatus,
    this.firstName,
    this.lastName,
    this.phone,
    this.email,
    this.address,
    this.studentFirstName,
    this.studentLastName,
    this.admissionNo,
    this.className,
  });

  /// `student_contacts.student_id`.
  final int studentId;

  /// `contacts.id`.
  final int contactId;

  /// `student_contacts.relationship`.
  final String? relationship;

  /// `student_contacts.is_primary`.
  final bool isPrimary;

  /// `contacts.contact_type` — `guardian` by default.
  final String? contactType;

  /// `contacts.occupation`.
  final String? occupation;

  /// `contacts.alive_status`.
  final String? aliveStatus;

  /// Contact's given name.
  final String? firstName;

  /// Contact's family name.
  final String? lastName;

  /// Contact's phone.
  final String? phone;

  /// Contact's email.
  final String? email;

  /// Contact's address.
  final String? address;

  /// The learner's given name.
  final String? studentFirstName;

  /// The learner's family name.
  final String? studentLastName;

  /// The learner's admission number.
  final String? admissionNo;

  /// The learner's latest active class.
  final String? className;

  /// The contact's name, or their phone when no name was recorded — the
  /// route allows phone-only quick entry.
  String get contactLabel {
    final String n = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return n.isNotEmpty ? n : (phone ?? 'Contact #$contactId');
  }

  /// The learner's name.
  String get studentLabel {
    final String n = '${studentFirstName ?? ''} ${studentLastName ?? ''}'
        .trim();
    return n.isEmpty ? 'Learner #$studentId' : n;
  }
}

/// One page of contacts, with the route's `pagination`.
class ContactPage {
  /// Creates a page.
  const ContactPage({
    required this.rows,
    required this.page,
    required this.limit,
    required this.total,
  });

  /// `data`.
  final List<ContactRow> rows;

  /// `pagination.page`.
  final int page;

  /// `pagination.limit`.
  final int limit;

  /// `pagination.total`.
  final int total;

  /// Whether another page exists.
  bool get hasMore => page * limit < total;
}

/// What the add and edit forms send.
class ContactInput {
  /// Creates an input.
  const ContactInput({
    required this.phone,
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.address = '',
    this.contactType = 'guardian',
    this.occupation = '',
    this.relationship = '',
    this.isPrimary = false,
    this.aliveStatus = 'alive',
  });

  /// Required by every contact route.
  final String phone;

  /// Given name.
  final String firstName;

  /// Family name.
  final String lastName;

  /// Email.
  final String email;

  /// Address.
  final String address;

  /// `guardian`, `parent`, `emergency`, …
  final String contactType;

  /// Occupation.
  final String occupation;

  /// e.g. Mother, Uncle.
  final String relationship;

  /// Primary contact for the learner.
  final bool isPrimary;

  /// `alive` | `deceased`, on edit.
  final String aliveStatus;
}

/// A learner in a duplicate group — `GET /api/students/duplicates`.
class DuplicateMember {
  /// Creates a member.
  const DuplicateMember({
    required this.id,
    this.firstName,
    this.lastName,
    this.admissionNo,
    this.className,
    this.classId,
    this.status,
    this.createdAt,
    this.admissionDate,
    this.enrollmentCount = 0,
    this.attendanceCount = 0,
    this.resultsCount = 0,
  });

  /// `students.id`.
  final int id;

  /// Given name.
  final String? firstName;

  /// Family name.
  final String? lastName;

  /// Admission number.
  final String? admissionNo;

  /// One active class.
  final String? className;

  /// Its id.
  final int? classId;

  /// `students.status`.
  final String? status;

  /// `students.created_at`.
  final String? createdAt;

  /// `students.admission_date`.
  final String? admissionDate;

  /// Enrolments on record.
  final int enrollmentCount;

  /// Rows in the legacy `student_attendance` table — see PARITY §4.2.
  final int attendanceCount;

  /// Results on record.
  final int resultsCount;

  /// Name to show.
  String get name {
    final String n = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return n.isEmpty ? 'Learner #$id' : n;
  }
}

/// A set of learners who may be the same person.
class DuplicateGroup {
  /// Creates a group.
  const DuplicateGroup({
    required this.groupId,
    required this.matchReason,
    required this.confidence,
    required this.students,
  });

  /// `group_id`, 1-based.
  final int groupId;

  /// Why they were grouped.
  final String matchReason;

  /// `high` | `medium` | `low`.
  final String confidence;

  /// Oldest record first.
  final List<DuplicateMember> students;
}

/// The route's whole response.
class DuplicateReport {
  /// Creates a report.
  const DuplicateReport({required this.totalStudents, required this.groups});

  /// Live learners in the school.
  final int totalStudents;

  /// The groups.
  final List<DuplicateGroup> groups;

  /// Learners across every group.
  int get totalDuplicates => groups.fold(
    0,
    (int sum, DuplicateGroup g) => sum + g.students.length,
  );
}

/// One merge group's outcome.
class MergeOutcome {
  /// Creates an outcome.
  const MergeOutcome({
    required this.primaryId,
    required this.success,
    this.actions = const <String>[],
    this.error,
  });

  /// The kept record.
  final int primaryId;

  /// Whether the group's transaction committed.
  final bool success;

  /// What was moved, in the route's own words.
  final List<String> actions;

  /// Why it failed.
  final String? error;
}

/// One learner's result in a bulk enrolment.
class BulkEnrollItem {
  /// Creates an item.
  const BulkEnrollItem({
    required this.studentId,
    required this.success,
    required this.message,
  });

  /// The learner.
  final int studentId;

  /// Whether they were enrolled.
  final bool success;

  /// The route's message.
  final String message;
}

/// `POST /api/enrollments/bulk` `multiple_students`.
class BulkEnrollResult {
  /// Creates a result.
  const BulkEnrollResult({required this.items});

  /// Per learner.
  final List<BulkEnrollItem> items;

  /// Enrolled.
  int get successful => items.where((BulkEnrollItem i) => i.success).length;

  /// The route's message.
  String get message =>
      'Bulk enrollment complete: $successful/${items.length} students enrolled successfully';
}
