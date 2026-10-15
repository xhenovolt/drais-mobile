import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/students/data/direct/longterm/duplicates.dart';
import 'package:drais/features/students/domain/entities/student_admin.dart';

/// Pins the Dart port of `GET /api/students/duplicates`' grouping rules and
/// `src/lib/contacts/import.ts`' normalisers.
void main() {
  DuplicateMember m(int id, {String? adm, int? classId}) =>
      DuplicateMember(id: id, admissionNo: adm, classId: classId);

  group('confidence', () {
    test('an exact name match alone is medium', () {
      final List<DuplicateGroup> g = buildDuplicateGroups(
        nameKeys: <String>['amina|nakato'],
        membersByName: <String, List<DuplicateMember>>{
          'amina|nakato': <DuplicateMember>[m(1), m(2)],
        },
        admissionNos: const <String>[],
        membersByAdmission: const <String, List<DuplicateMember>>{},
      );
      expect(g.single.confidence, 'medium');
      expect(g.single.matchReason, 'Exact name match');
    });

    test('a shared admission number outranks a shared class', () {
      final DuplicateGroup g = buildDuplicateGroups(
        nameKeys: <String>['a|b'],
        membersByName: <String, List<DuplicateMember>>{
          'a|b': <DuplicateMember>[
            m(1, adm: 'X1', classId: 4),
            m(2, adm: 'X1', classId: 4),
          ],
        },
        admissionNos: const <String>[],
        membersByAdmission: const <String, List<DuplicateMember>>{},
      ).single;
      expect(g.confidence, 'high');
      expect(g.matchReason, 'Same name + same admission number');
    });

    test('blank admission numbers never count as shared', () {
      // The route's truthiness test: '' && '' is falsy.
      final DuplicateGroup g = buildDuplicateGroups(
        nameKeys: <String>['a|b'],
        membersByName: <String, List<DuplicateMember>>{
          'a|b': <DuplicateMember>[m(1, adm: ''), m(2, adm: '')],
        },
        admissionNos: const <String>[],
        membersByAdmission: const <String, List<DuplicateMember>>{},
      ).single;
      expect(g.confidence, 'medium');
    });

    test('same class gives high', () {
      final DuplicateGroup g = buildDuplicateGroups(
        nameKeys: <String>['a|b'],
        membersByName: <String, List<DuplicateMember>>{
          'a|b': <DuplicateMember>[m(1, classId: 7), m(2, classId: 7)],
        },
        admissionNos: const <String>[],
        membersByAdmission: const <String, List<DuplicateMember>>{},
      ).single;
      expect(g.matchReason, 'Same name + same class');
    });
  });

  test('an admission group already captured by name is not repeated', () {
    final List<DuplicateGroup> g = buildDuplicateGroups(
      nameKeys: <String>['a|b'],
      membersByName: <String, List<DuplicateMember>>{
        'a|b': <DuplicateMember>[m(1, adm: 'X1'), m(2, adm: 'X1')],
      },
      admissionNos: <String>['X1', 'Y2'],
      membersByAdmission: <String, List<DuplicateMember>>{
        'X1': <DuplicateMember>[m(1, adm: 'X1'), m(2, adm: 'X1')],
        'Y2': <DuplicateMember>[m(3, adm: 'Y2'), m(4, adm: 'Y2')],
      },
    );
    expect(g.length, 2);
    expect(g[1].matchReason, 'Same admission number');
    expect(g.map((DuplicateGroup x) => x.groupId), <int>[1, 2]);
  });

  test('a group that resolves to one live member is dropped', () {
    expect(
      buildDuplicateGroups(
        nameKeys: <String>['a|b'],
        membersByName: <String, List<DuplicateMember>>{
          'a|b': <DuplicateMember>[m(1)],
        },
        admissionNos: const <String>[],
        membersByAdmission: const <String, List<DuplicateMember>>{},
      ),
      isEmpty,
    );
  });

  test('phones match regardless of spacing and punctuation', () {
    expect(normalizePhone(' +256 (700) 000-001 '), '+256700000001');
    expect(normalizePhone('0700.000.001'), '0700000001');
    expect(normalizeEmail(' Amina@Example.COM '), 'amina@example.com');
  });
}
