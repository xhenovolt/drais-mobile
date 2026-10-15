import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/attendance/data/direct/longterm/person_intelligence.dart';
import 'package:drais/features/attendance/domain/entities/attendance_insights.dart';

/// Pins the Dart port of `profilePerson()` to the platform.
///
/// Transcribed from LongTerm's
/// `src/lib/attendance/__tests__/person-intelligence.test.mjs`.
void main() {
  List<PersonDay> seq(String pattern) => <PersonDay>[
    for (int i = 0; i < pattern.length; i++)
      PersonDay(
        date: '2026-07-${(i + 1).toString().padLeft(2, '0')}',
        status: switch (pattern[i]) {
          'P' => 'present',
          'L' => 'late',
          'A' => 'absent',
          _ => 'half_day',
        },
      ),
  ];

  test('under four days is insufficient data', () {
    final PersonProfile p = profilePerson(seq('PPP'));
    expect(p.behaviour, Behaviour.insufficientData);
    expect(p.watch, isFalse);
  });

  group('roster noise separates itself', () {
    test('never present in six days is roster review, not watch', () {
      final PersonProfile p = profilePerson(seq('AAAAAA'));
      expect(p.behaviour, Behaviour.neverPresent);
      expect(p.rosterReview, isTrue);
      expect(p.watch, isFalse);
      expect(p.note, contains('former member or not enrolled'));
    });

    test('showing up even once makes it behaviour', () {
      final PersonProfile p = profilePerson(seq('PAAAAA'));
      expect(p.behaviour, isNot(Behaviour.neverPresent));
      expect(p.rosterReview, isFalse);
      expect(p.watch, isTrue);
    });
  });

  test('mostly present is reliable', () {
    final PersonProfile p = profilePerson(seq('PPPPPPPPPP'));
    expect(p.behaviour, Behaviour.reliable);
    expect(p.watch, isFalse);
    expect(p.absentRate, 0);
  });

  group('frequently absent', () {
    test('20% or more absence is watched', () {
      final PersonProfile p = profilePerson(seq('PAPAPAPPPP'));
      expect(p.behaviour, Behaviour.frequentlyAbsent);
      expect(p.watch, isTrue);
      expect(p.note, contains('Absent 30%'));
    });

    test('reports the current absence streak', () {
      final PersonProfile p = profilePerson(seq('PPPPPPPAAA'));
      expect(p.currentAbsentStreak, 3);
      expect(p.behaviour, Behaviour.frequentlyAbsent);
    });
  });

  test('a clean first half then absences is declining', () {
    final PersonProfile p = profilePerson(seq('PPPPPPPPPPPPPPPPPAAA'));
    expect(p.behaviour, Behaviour.declining);
    expect(p.watch, isTrue);
    expect(p.note, contains('change from their own pattern'));
  });

  group('lateness', () {
    test('35% or more late is chronic', () {
      final PersonProfile p = profilePerson(seq('LLLLPPPPPP'));
      expect(p.behaviour, Behaviour.chronicallyLate);
      expect(p.watch, isTrue);
    });

    test('15–34% late is occasional and not watched', () {
      final PersonProfile p = profilePerson(seq('LLPPPPPPPP'));
      expect(p.behaviour, Behaviour.occasionallyLate);
      expect(p.watch, isFalse);
    });
  });

  test('early absences then a clean run is improving', () {
    final PersonProfile p = profilePerson(seq('PPPAAAPPPPPPPPPPPPPP'));
    expect(p.behaviour, Behaviour.improving);
    expect(p.watch, isFalse);
  });

  test('computes the rates', () {
    final PersonProfile p = profilePerson(seq('PPPPPLLAAP'));
    expect(p.absentRate, closeTo(0.2, 0.001));
    expect(p.lateRate, closeTo(0.2, 0.001));
  });
}
