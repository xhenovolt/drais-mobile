/// Learners, as DRAIS LongTerm's student routes return them.
///
/// Field names follow the route payloads (`/api/students/enrolled`,
/// `/admitted`, `/[id]/profile`, `/[id]/previous-enrollment`), so a value on
/// the phone can be traced to one column on the web.
library;

/// A learner row on the list page: the Enrolled tab (term-aware) or the
/// Admitted tab (not enrolled in the current term).
class StudentListRow {
  /// Creates a row.
  const StudentListRow({
    required this.id,
    required this.personId,
    required this.firstName,
    required this.lastName,
    this.otherName,
    this.admissionNo,
    this.studentStatus,
    this.admissionDate,
    this.residencyStatus,
    this.gender,
    this.dateOfBirth,
    this.photoUrl,
    this.phone,
    this.email,
    this.enrollmentId,
    this.className,
    this.streamName,
    this.termName,
    this.academicYearName,
    this.studyModeName,
    this.programName,
    this.enrollmentStatus,
    this.enrollmentType,
    this.programs = const <String>[],
  });

  /// `students.id`.
  final int id;

  /// `students.person_id`, the key attendance is recorded against.
  final int personId;

  /// `people.first_name`.
  final String firstName;

  /// `people.last_name`.
  final String lastName;

  /// `people.other_name`.
  final String? otherName;

  /// `students.admission_no`.
  final String? admissionNo;

  /// `students.status`.
  final String? studentStatus;

  /// `students.admission_date`, `YYYY-MM-DD…` as stored.
  final String? admissionDate;

  /// `students.residency_status` (`day` / `boarding` / blank).
  final String? residencyStatus;

  /// `people.gender`, as stored.
  final String? gender;

  /// `people.date_of_birth`.
  final String? dateOfBirth;

  /// `people.photo_url`.
  final String? photoUrl;

  /// `people.phone`.
  final String? phone;

  /// `people.email`.
  final String? email;

  /// Enrolled tab only.
  final int? enrollmentId;

  /// Enrolled tab only.
  final String? className;

  /// Enrolled tab only.
  final String? streamName;

  /// Enrolled tab only.
  final String? termName;

  /// Enrolled tab only.
  final String? academicYearName;

  /// Enrolled tab only.
  final String? studyModeName;

  /// Enrolled tab only.
  final String? programName;

  /// Enrolled tab only: `active` | `completed` | `transferred` | `dropped`.
  final String? enrollmentStatus;

  /// Enrolled tab only: `new` | `continuing` | `repeat`.
  final String? enrollmentType;

  /// Enrolled tab only: every program on the enrolment.
  final List<String> programs;

  /// `personDisplayName('en', row)`: first, other, last.
  String get displayName {
    final String name = <String?>[firstName, otherName, lastName]
        .where((String? p) => p != null && p.trim().isNotEmpty)
        .join(' ')
        .trim();
    return name.isEmpty ? 'Unnamed learner' : name;
  }

  /// Initials for an avatar.
  String get initials {
    final String a = firstName.trim().isNotEmpty ? firstName.trim()[0] : '';
    final String b = lastName.trim().isNotEmpty ? lastName.trim()[0] : '';
    final String combined = '$a$b'.trim();
    return combined.isEmpty ? '?' : combined.toUpperCase();
  }
}

/// One list tab's result, with the route's `meta`.
class StudentListResult {
  /// Creates a result.
  const StudentListResult({
    required this.rows,
    required this.truncated,
    this.termId,
    this.termName,
  });

  /// `data`.
  final List<StudentListRow> rows;

  /// `meta.truncated`: more than 10,000 rows matched.
  final bool truncated;

  /// The term the tab was resolved against.
  final int? termId;

  /// Its name, when known.
  final String? termName;
}

/// One enrolment in a learner's history.
class EnrollmentRecord {
  /// Creates an enrolment record.
  const EnrollmentRecord({
    required this.enrollmentId,
    this.classId,
    this.className,
    this.classLevel,
    this.streamName,
    this.academicYearId,
    this.academicYearName,
    this.termId,
    this.termName,
    this.studyModeId,
    this.studyModeName,
    this.curriculumId,
    this.curriculumName,
    this.programId,
    this.programName,
    this.enrollmentType,
    this.status,
    this.enrollmentDate,
    this.endDate,
    this.endReason,
    this.programs = const <String>[],
  });

  /// `enrollments.id`.
  final int enrollmentId;

  /// Class.
  final int? classId;

  /// Class name.
  final String? className;

  /// `classes.class_level`, used to suggest promote/demote targets.
  final int? classLevel;

  /// Stream name.
  final String? streamName;

  /// Academic year.
  final int? academicYearId;

  /// Academic year name.
  final String? academicYearName;

  /// Term.
  final int? termId;

  /// Term name.
  final String? termName;

  /// Study mode.
  final int? studyModeId;

  /// Study mode name.
  final String? studyModeName;

  /// Curriculum.
  final int? curriculumId;

  /// Curriculum name.
  final String? curriculumName;

  /// Program.
  final int? programId;

  /// Program name.
  final String? programName;

  /// `new` | `continuing` | `repeat`.
  final String? enrollmentType;

  /// `active` | `completed` | …
  final String? status;

  /// `enrollment_date`.
  final String? enrollmentDate;

  /// `end_date`.
  final String? endDate;

  /// `end_reason`, e.g. `promoted`.
  final String? endReason;

  /// Programs from `enrollment_programs`.
  final List<String> programs;
}

/// A person linked to a learner: a parent, a contact or a next of kin.
class StudentRelation {
  /// Creates a relation.
  const StudentRelation({
    required this.name,
    this.contactId,
    this.firstName,
    this.lastName,
    this.address,
    this.aliveStatus,
    this.relationship,
    this.phone,
    this.email,
    this.occupation,
    this.isPrimary = false,
  });

  /// Display name.
  final String name;

  /// `contacts.id`, for contacts (not parents or next of kin) — what the
  /// edit form needs.
  final int? contactId;

  /// Contact's given name, kept separate for editing.
  final String? firstName;

  /// Contact's family name, kept separate for editing.
  final String? lastName;

  /// Contact's address. Carried so an edit does not blank it — the contact
  /// update route writes every field it is given.
  final String? address;

  /// `contacts.alive_status`, carried for the same reason.
  final String? aliveStatus;

  /// How they are related.
  final String? relationship;

  /// Phone.
  final String? phone;

  /// Email.
  final String? email;

  /// Occupation.
  final String? occupation;

  /// The primary contact.
  final bool isPrimary;
}

/// A learner's lifecycle status — the values `/api/students/bulk/status`
/// accepts.
enum StudentStatus {
  /// Currently on the roll.
  active('active', 'Active'),

  /// Departed. A reason is required.
  left('left', 'Left'),

  /// Completed their program.
  graduated('graduated', 'Graduated'),

  /// Temporarily inactive.
  suspended('suspended', 'Suspended');

  const StudentStatus(this.wireValue, this.label);

  /// `students.status`.
  final String wireValue;

  /// Label.
  final String label;

  /// Resolves a stored value.
  static StudentStatus? fromWire(String? v) {
    for (final StudentStatus s in values) {
      if (s.wireValue == v) return s;
    }
    return null;
  }
}

/// One row of `student_next_of_kin`.
class NextOfKinEntry {
  /// Creates an entry.
  const NextOfKinEntry({
    required this.name,
    this.sequence,
    this.address,
    this.occupation,
    this.contact,
  });

  /// Order shown; the route numbers rows without one.
  final int? sequence;

  /// Name. Rows without one are skipped by the route.
  final String name;

  /// Address.
  final String? address;

  /// Occupation.
  final String? occupation;

  /// Phone or other contact.
  final String? contact;
}

/// The three singleton profile blocks `PUT /api/students/[id]/profile`
/// upserts.
///
/// ## Every column is carried, deliberately
///
/// The route writes **every** column of a block it receives, defaulting
/// absent ones to NULL. A form that edits three fields must therefore send
/// the other columns back unchanged, or it erases them — district,
/// nationality, the guardian's occupation. This class holds them all for
/// that reason, including the ids no mobile form edits.
class ProfileBlocks {
  /// Creates the blocks.
  const ProfileBlocks({
    this.orphanStatus,
    this.previousSchool,
    this.notes,
    this.placeOfBirth,
    this.placeOfResidence,
    this.districtId,
    this.nationalityId,
    this.orphanStatusId,
    this.guardianName,
    this.guardianContact,
    this.guardianOccupation,
    this.fatherName,
    this.fatherLivingStatusId,
    this.fatherOccupation,
    this.fatherContact,
    this.familyNotes,
  });

  /// `student_additional_info.orphan_status` (free text).
  final String? orphanStatus;

  /// `student_additional_info.previous_school`.
  final String? previousSchool;

  /// `student_additional_info.notes`.
  final String? notes;

  /// `student_profiles.place_of_birth`.
  final String? placeOfBirth;

  /// `student_profiles.place_of_residence`.
  final String? placeOfResidence;

  /// `student_profiles.district_id`, preserved.
  final int? districtId;

  /// `student_profiles.nationality_id`, preserved.
  final int? nationalityId;

  /// `student_family_status.orphan_status_id`, preserved.
  final int? orphanStatusId;

  /// `primary_guardian_name`.
  final String? guardianName;

  /// `primary_guardian_contact`.
  final String? guardianContact;

  /// `primary_guardian_occupation`.
  final String? guardianOccupation;

  /// `father_name`.
  final String? fatherName;

  /// `father_living_status_id`, preserved.
  final int? fatherLivingStatusId;

  /// `father_occupation`.
  final String? fatherOccupation;

  /// `father_contact`.
  final String? fatherContact;

  /// `student_family_status.notes`.
  final String? familyNotes;

  /// Returns a copy with the editable text fields replaced; ids carry over.
  ProfileBlocks withText({
    required String? previousSchool,
    required String? notes,
    required String? placeOfBirth,
    required String? placeOfResidence,
    required String? guardianName,
    required String? guardianContact,
    required String? guardianOccupation,
    required String? fatherName,
    required String? fatherOccupation,
    required String? fatherContact,
  }) => ProfileBlocks(
    orphanStatus: orphanStatus,
    previousSchool: previousSchool,
    notes: notes,
    placeOfBirth: placeOfBirth,
    placeOfResidence: placeOfResidence,
    districtId: districtId,
    nationalityId: nationalityId,
    orphanStatusId: orphanStatusId,
    guardianName: guardianName,
    guardianContact: guardianContact,
    guardianOccupation: guardianOccupation,
    fatherName: fatherName,
    fatherLivingStatusId: fatherLivingStatusId,
    fatherOccupation: fatherOccupation,
    fatherContact: fatherContact,
    familyNotes: familyNotes,
  );
}

/// The personal fields `PUT /api/students/edit` accepts. Only non-null
/// fields are sent, as the route updates only fields present in the body.
class StudentEdit {
  /// Creates an edit.
  const StudentEdit({
    this.firstName,
    this.lastName,
    this.otherName,
    this.gender,
    this.dateOfBirth,
    this.phone,
    this.email,
    this.address,
  });

  /// `first_name`.
  final String? firstName;

  /// `last_name`.
  final String? lastName;

  /// `other_name`.
  final String? otherName;

  /// `gender`.
  final String? gender;

  /// `date_of_birth`, `YYYY-MM-DD`.
  final String? dateOfBirth;

  /// `phone`.
  final String? phone;

  /// `email`.
  final String? email;

  /// `address`.
  final String? address;

  /// The body keys and values, in the route's column order.
  Map<String, String> get fields => <String, String>{
    'first_name': ?firstName,
    'last_name': ?lastName,
    'other_name': ?otherName,
    'gender': ?gender,
    'date_of_birth': ?dateOfBirth,
    'phone': ?phone,
    'email': ?email,
    'address': ?address,
  };
}

/// A learner in Trash — `/api/students/list?view=trash`.
class TrashedStudent {
  /// Creates a trashed row.
  const TrashedStudent({
    required this.id,
    required this.name,
    this.admissionNo,
    this.deletedAt,
    this.deleteReason,
    this.enrollmentCount = 0,
    this.resultCount = 0,
  });

  /// `students.id`.
  final int id;

  /// First and last name.
  final String name;

  /// `admission_no`.
  final String? admissionNo;

  /// When archived.
  final String? deletedAt;

  /// Why.
  final String? deleteReason;

  /// Enrolments on record.
  final int enrollmentCount;

  /// Results on record.
  final int resultCount;
}

/// `GET /api/students/[id]/profile`.
class StudentProfile {
  /// Creates a profile.
  const StudentProfile({
    required this.row,
    this.enrollments = const <EnrollmentRecord>[],
    this.parents = const <StudentRelation>[],
    this.contacts = const <StudentRelation>[],
    this.nextOfKin = const <StudentRelation>[],
    this.previousSchool,
    this.notes,
    this.orphanStatus,
    this.placeOfBirth,
    this.placeOfResidence,
    this.district,
    this.nationality,
    this.guardianName,
    this.guardianContact,
    this.fatherName,
    this.fatherContact,
    this.fatherStatus,
    this.documentCount = 0,
    this.fingerprintsTotal = 0,
    this.fingerprintsActive = 0,
    this.address,
    this.blocks = const ProfileBlocks(),
    this.nextOfKinEntries = const <NextOfKinEntry>[],
  });

  /// The learner's core record.
  final StudentListRow row;

  /// `people.address`.
  final String? address;

  /// Every column of the three profile blocks, for editing.
  final ProfileBlocks blocks;

  /// Next of kin with every column, for editing.
  final List<NextOfKinEntry> nextOfKinEntries;

  /// Enrolment history, newest first.
  final List<EnrollmentRecord> enrollments;

  /// `student_parents`.
  final List<StudentRelation> parents;

  /// `student_contacts`.
  final List<StudentRelation> contacts;

  /// `student_next_of_kin`.
  final List<StudentRelation> nextOfKin;

  /// `student_additional_info.previous_school`.
  final String? previousSchool;

  /// `student_additional_info.notes`.
  final String? notes;

  /// Orphan status: the family-status label, else the free-text field.
  final String? orphanStatus;

  /// `student_profiles.place_of_birth`.
  final String? placeOfBirth;

  /// `student_profiles.place_of_residence`.
  final String? placeOfResidence;

  /// District name.
  final String? district;

  /// Nationality name.
  final String? nationality;

  /// Primary guardian.
  final String? guardianName;

  /// Primary guardian contact.
  final String? guardianContact;

  /// Father.
  final String? fatherName;

  /// Father's contact.
  final String? fatherContact;

  /// Father living status label.
  final String? fatherStatus;

  /// Documents on file.
  final int documentCount;

  /// Fingerprints enrolled.
  final int fingerprintsTotal;

  /// Fingerprints active.
  final int fingerprintsActive;

  /// The active enrolment, when there is one.
  EnrollmentRecord? get activeEnrollment {
    for (final EnrollmentRecord e in enrollments) {
      if (e.status == 'active') return e;
    }
    return null;
  }
}

/// A term, as `resolveTermContext()` derives it.
class TermChoice {
  /// Creates a term choice.
  const TermChoice({
    required this.id,
    required this.name,
    required this.derivedStatus,
    this.academicYearId,
    this.academicYearName,
    this.startDate,
    this.endDate,
  });

  /// `terms.id`.
  final int id;

  /// `terms.name`.
  final String name;

  /// `upcoming` | `current` | `completed` | `unknown`, from dates.
  final String derivedStatus;

  /// Academic year.
  final int? academicYearId;

  /// Academic year name.
  final String? academicYearName;

  /// `YYYY-MM-DD`.
  final String? startDate;

  /// `YYYY-MM-DD`.
  final String? endDate;
}

/// A generic picker option: class, stream, study mode, curriculum, program.
class Choice {
  /// Creates a choice.
  const Choice({
    required this.id,
    required this.label,
    this.isDefault = false,
    this.parentId,
    this.level,
  });

  /// Row id.
  final int id;

  /// What to show.
  final String label;

  /// `is_default`.
  final bool isDefault;

  /// A stream's class.
  final int? parentId;

  /// A class's `class_level`.
  final int? level;
}

/// Everything the enrol form needs to offer — `/api/terms/current`,
/// `/api/classes`, `/api/streams`, `/api/study-modes`, `/api/curriculums`,
/// `/api/programs`.
class EnrollmentOptions {
  /// Creates the options.
  const EnrollmentOptions({
    required this.terms,
    required this.classes,
    required this.streams,
    required this.studyModes,
    required this.curriculums,
    required this.programs,
    this.currentTerm,
  });

  /// Every term, oldest first.
  final List<TermChoice> terms;

  /// Date-current term, or null — the platform never falls back to a stale
  /// one.
  final TermChoice? currentTerm;

  /// Classes, by level then name.
  final List<Choice> classes;

  /// Streams, each with its class.
  final List<Choice> streams;

  /// Study modes, default first.
  final List<Choice> studyModes;

  /// Curriculums.
  final List<Choice> curriculums;

  /// Programs, default first.
  final List<Choice> programs;

  /// Academic years, derived from the terms as the web form does.
  List<Choice> get academicYears {
    final Map<int, String> seen = <int, String>{};
    for (final TermChoice t in terms) {
      final int? id = t.academicYearId;
      if (id != null) seen.putIfAbsent(id, () => t.academicYearName ?? '#$id');
    }
    return seen.entries
        .map((MapEntry<int, String> e) => Choice(id: e.key, label: e.value))
        .toList(growable: false);
  }
}

/// `POST /api/students` — what the admit form collects.
class AdmissionRequest {
  /// Creates a request.
  const AdmissionRequest({
    required this.firstName,
    required this.lastName,
    this.otherName,
    this.gender,
    this.dateOfBirth,
    this.phone,
    this.email,
  });

  /// Required by the route.
  final String firstName;

  /// Required by the route, although the web form marks it optional.
  final String lastName;

  /// Sent by the web form; **not saved by the route**.
  final String? otherName;

  /// Sent by the web form; **not saved by the route**.
  final String? gender;

  /// Sent by the web form; **not saved by the route**.
  final String? dateOfBirth;

  /// Saved to `people.phone`.
  final String? phone;

  /// Saved to `people.email`.
  final String? email;
}

/// The route's success payload.
class AdmissionResult {
  /// Creates a result.
  const AdmissionResult({
    required this.studentId,
    required this.personId,
    this.enrollmentId,
  });

  /// `student_id`.
  final int studentId;

  /// `person_id`.
  final int personId;

  /// `enrollment_id`, when a class was supplied.
  final int? enrollmentId;
}

/// The web enrol form's decision, and the `enrollment_type` it sends.
enum EnrollmentDecision {
  /// Next class up.
  promote('Promote', 'continuing'),

  /// Same class.
  continueSame('Continue', 'continuing'),

  /// Class below.
  demote('Repeat / demote', 'repeat'),

  /// No previous enrolment.
  firstTime('First time', 'new');

  const EnrollmentDecision(this.label, this.enrollmentType);

  /// Label.
  final String label;

  /// `enrollment_type`.
  final String enrollmentType;
}

/// `POST /api/enrollments` — the single-learner form.
class EnrollmentRequest {
  /// Creates a request.
  const EnrollmentRequest({
    required this.studentId,
    required this.classId,
    required this.academicYearId,
    required this.termId,
    required this.studyModeId,
    required this.curriculumId,
    required this.programId,
    required this.decision,
    this.streamId,
  });

  /// Learner.
  final int studentId;

  /// Class.
  final int classId;

  /// Stream.
  final int? streamId;

  /// Academic year.
  final int academicYearId;

  /// Term.
  final int termId;

  /// Study mode.
  final int studyModeId;

  /// Curriculum.
  final int curriculumId;

  /// Program.
  final int programId;

  /// Promote / continue / demote / first time.
  final EnrollmentDecision decision;
}
