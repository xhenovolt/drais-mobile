import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/students/application/enrollment_suggestions.dart';
import 'package:drais/features/students/data/direct/longterm/term_resolver.dart';
import 'package:drais/features/students/domain/entities/students.dart';

/// Pins the Students ports to LongTerm behaviour.
void main() {
  group('deriveTermStatus — resolveTermContext()', () {
    test('today inside the dates is current, inclusive at both ends', () {
      expect(deriveTermStatus('2026-09-01', '2026-12-05', '2026-09-01'), 'current');
      expect(deriveTermStatus('2026-09-01', '2026-12-05', '2026-12-05'), 'current');
    });

    test('before start is upcoming, after end is completed', () {
      expect(deriveTermStatus('2026-09-01', '2026-12-05', '2026-08-31'), 'upcoming');
      expect(deriveTermStatus('2026-09-01', '2026-12-05', '2026-12-06'), 'completed');
    });

    test('missing dates are unknown, never current', () {
      expect(deriveTermStatus(null, '2026-12-05', '2026-10-01'), 'unknown');
      expect(deriveTermStatus('2026-09-01', null, '2026-10-01'), 'unknown');
    });

    test('a DATETIME string is read as its calendar day', () {
      expect(
        deriveTermStatus('2026-09-01 00:00:00', '2026-12-05 00:00:00', '2026-12-05'),
        'current',
      );
    });
  });

  group('effectiveTerm — date truth, no stale fallback', () {
    TermChoice t(int id, String status) =>
        TermChoice(id: id, name: 'T$id', derivedStatus: status);

    test('picks the term covering today', () {
      expect(
        effectiveTerm(<TermChoice>[
          t(1, 'completed'),
          t(2, 'current'),
          t(3, 'upcoming'),
        ])?.id,
        2,
      );
    });

    test('returns null between terms rather than the last one', () {
      // The platform's "Term I forever" bug was falling back here.
      expect(
        effectiveTerm(<TermChoice>[t(1, 'completed'), t(2, 'upcoming')]),
        isNull,
      );
    });
  });

  group('suggestClassId — the web enrol form', () {
    const List<Choice> classes = <Choice>[
      Choice(id: 10, label: 'P3', level: 3),
      Choice(id: 11, label: 'P4', level: 4),
      Choice(id: 12, label: 'P5', level: 5),
    ];
    const EnrollmentRecord prev = EnrollmentRecord(
      enrollmentId: 1,
      classId: 11,
      classLevel: 4,
    );

    test('continue keeps the class', () {
      expect(suggestClassId(EnrollmentDecision.continueSame, prev, classes), 11);
    });
    test('promote moves one level up', () {
      expect(suggestClassId(EnrollmentDecision.promote, prev, classes), 12);
    });
    test('demote moves one level down', () {
      expect(suggestClassId(EnrollmentDecision.demote, prev, classes), 10);
    });
    test('no class at the target level suggests nothing', () {
      const EnrollmentRecord top = EnrollmentRecord(
        enrollmentId: 2,
        classId: 12,
        classLevel: 5,
      );
      expect(suggestClassId(EnrollmentDecision.promote, top, classes), isNull);
    });
    test('first time suggests nothing', () {
      expect(suggestClassId(EnrollmentDecision.firstTime, null, classes), isNull);
    });
  });

  test('decisions send the web form\'s enrollment_type', () {
    expect(EnrollmentDecision.promote.enrollmentType, 'continuing');
    expect(EnrollmentDecision.continueSame.enrollmentType, 'continuing');
    expect(EnrollmentDecision.demote.enrollmentType, 'repeat');
    expect(EnrollmentDecision.firstTime.enrollmentType, 'new');
  });

  test('display name is first, other, last — personDisplayName("en")', () {
    const StudentListRow row = StudentListRow(
      id: 1,
      personId: 1,
      firstName: 'Amina',
      lastName: 'Nakato',
      otherName: 'Grace',
    );
    expect(row.displayName, 'Amina Grace Nakato');
    expect(
      const StudentListRow(id: 2, personId: 2, firstName: '', lastName: '').displayName,
      'Unnamed learner',
    );
  });

  group('edits send only what the route should write', () {
    test('StudentEdit omits fields left null', () {
      // /api/students/edit updates only keys present in the body.
      expect(
        const StudentEdit(firstName: 'Amina', phone: '0700').fields,
        <String, String>{'first_name': 'Amina', 'phone': '0700'},
      );
      expect(const StudentEdit().fields, isEmpty);
    });

    test('an empty string is sent, so a field can be cleared', () {
      expect(const StudentEdit(email: '').fields, <String, String>{'email': ''});
    });

    test('the profile form preserves ids it never shows', () {
      // PUT /api/students/[id]/profile writes every column of a block, so
      // dropping these would erase district, nationality and statuses.
      const ProfileBlocks before = ProfileBlocks(
        districtId: 4,
        nationalityId: 9,
        orphanStatusId: 2,
        fatherLivingStatusId: 1,
        orphanStatus: 'single',
        familyNotes: 'kept',
        guardianName: 'Old',
      );
      final ProfileBlocks after = before.withText(
        previousSchool: 'X Primary',
        notes: null,
        placeOfBirth: null,
        placeOfResidence: null,
        guardianName: 'New',
        guardianContact: null,
        guardianOccupation: null,
        fatherName: null,
        fatherOccupation: null,
        fatherContact: null,
      );
      expect(after.districtId, 4);
      expect(after.nationalityId, 9);
      expect(after.orphanStatusId, 2);
      expect(after.fatherLivingStatusId, 1);
      expect(after.orphanStatus, 'single');
      expect(after.familyNotes, 'kept');
      expect(after.guardianName, 'New');
      expect(after.previousSchool, 'X Primary');
    });
  });

  test('statuses are the four the route accepts', () {
    expect(
      StudentStatus.values.map((StudentStatus s) => s.wireValue),
      <String>['active', 'left', 'graduated', 'suspended'],
    );
    expect(StudentStatus.fromWire('graduated'), StudentStatus.graduated);
    expect(StudentStatus.fromWire('expelled'), isNull);
  });

  test('academic years are derived from terms, once each', () {
    const EnrollmentOptions o = EnrollmentOptions(
      terms: <TermChoice>[
        TermChoice(id: 1, name: 'T1', derivedStatus: 'completed', academicYearId: 7, academicYearName: '2026'),
        TermChoice(id: 2, name: 'T2', derivedStatus: 'current', academicYearId: 7, academicYearName: '2026'),
        TermChoice(id: 3, name: 'T1', derivedStatus: 'upcoming', academicYearId: 8, academicYearName: '2027'),
      ],
      classes: <Choice>[],
      streams: <Choice>[],
      studyModes: <Choice>[],
      curriculums: <Choice>[],
      programs: <Choice>[],
    );
    expect(o.academicYears.map((Choice c) => c.label), <String>['2026', '2027']);
  });
}
