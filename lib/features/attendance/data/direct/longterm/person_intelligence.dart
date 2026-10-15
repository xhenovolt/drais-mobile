/// Person attendance intelligence.
///
/// **Ported line-for-line from `src/lib/attendance/person-intelligence.ts`**
/// (DRAIS LongTerm v1.91). Thresholds, classification order and note wording
/// are the platform's. `test/features/attendance/person_intelligence_test.dart`
/// carries the platform's own test cases.
library;

import 'package:drais/features/attendance/domain/entities/attendance_insights.dart';

double _rate(int n, int d) => d > 0 ? n / d : 0;

String _pct(double r) => '${(r * 100).round()}%';

({int current, int longest}) _streaks(List<PersonDay> days) {
  int longest = 0;
  int run = 0;
  int current = 0;
  for (final PersonDay d in days) {
    if (d.status == 'absent') {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 0;
    }
  }
  for (int i = days.length - 1; i >= 0; i--) {
    if (days[i].status == 'absent') {
      current++;
    } else {
      break;
    }
  }
  return (current: current, longest: longest);
}

const Set<String> _gradedStatuses = <String>{
  'present',
  'late',
  'absent',
  'half_day',
};

/// `profilePerson()` — [days] oldest first.
PersonProfile profilePerson(List<PersonDay> days) {
  final List<PersonDay> graded = days
      .where((PersonDay d) => _gradedStatuses.contains(d.status))
      .toList(growable: false);
  final int n = graded.length;

  if (n < 4) {
    return PersonProfile(
      trackedDays: n,
      presentRate: 0,
      lateRate: 0,
      absentRate: 0,
      currentAbsentStreak: 0,
      longestAbsentStreak: 0,
      recentAbsentRate: 0,
      priorAbsentRate: 0,
      behaviour: Behaviour.insufficientData,
      label: 'Not enough data',
      note: 'Only $n tracked day(s) — need more history to profile.',
      watch: false,
      rosterReview: false,
    );
  }

  final int absent = graded.where((PersonDay d) => d.status == 'absent').length;
  final int late = graded.where((PersonDay d) => d.status == 'late').length;
  final int showed = graded
      .where(
        (PersonDay d) =>
            d.status == 'present' || d.status == 'late' || d.status == 'half_day',
      )
      .length;
  final double absentRate = _rate(absent, n);
  final double lateRate = _rate(late, n);
  final double presentRate = _rate(showed, n);

  // Roster noise, separated from behaviour automatically (platform comment).
  if (n >= 5 && showed == 0) {
    final ({int current, int longest}) s = _streaks(graded);
    return PersonProfile(
      trackedDays: n,
      presentRate: 0,
      lateRate: 0,
      absentRate: 1,
      currentAbsentStreak: s.current,
      longestAbsentStreak: s.longest,
      recentAbsentRate: 1,
      priorAbsentRate: 1,
      behaviour: Behaviour.neverPresent,
      label: 'Never present',
      note:
          'No check-in on any of $n tracked days — likely a former member or '
          'not enrolled on the device. Review the roster / enrollment rather '
          'than treat as attendance behaviour.',
      watch: false,
      rosterReview: true,
    );
  }

  final int half = n ~/ 2;
  final double priorAbsentRate = _rate(
    graded.take(half).where((PersonDay d) => d.status == 'absent').length,
    half,
  );
  final double recentAbsentRate = _rate(
    graded.skip(half).where((PersonDay d) => d.status == 'absent').length,
    n - half,
  );
  final ({int current, int longest}) s = _streaks(graded);

  final bool worsening =
      recentAbsentRate > priorAbsentRate + 0.12 && recentAbsentRate >= 0.15;
  final bool improving =
      priorAbsentRate > recentAbsentRate + 0.12 && priorAbsentRate >= 0.15;

  Behaviour behaviour;
  String label;
  String note;
  bool watch = false;

  if (absentRate >= 0.2) {
    behaviour = Behaviour.frequentlyAbsent;
    label = 'Frequently absent';
    watch = true;
    note =
        'Absent ${_pct(absentRate)} of tracked days ($absent/$n)'
        '${s.current >= 2 ? ', currently on a ${s.current}-day absence streak' : ''}'
        ' — well above normal.';
  } else if (worsening) {
    behaviour = Behaviour.declining;
    label = 'Declining — unusual for them';
    watch = true;
    note =
        'Absence rose from ${_pct(priorAbsentRate)} to '
        '${_pct(recentAbsentRate)} recently — a change from their own '
        'pattern. Worth a conversation.';
  } else if (lateRate >= 0.35) {
    behaviour = Behaviour.chronicallyLate;
    label = 'Chronically late';
    watch = true;
    note =
        'Late ${_pct(lateRate)} of tracked days ($late/$n) — a persistent '
        'pattern.';
  } else if (improving) {
    behaviour = Behaviour.improving;
    label = 'Improving';
    note =
        'Absence fell from ${_pct(priorAbsentRate)} to '
        '${_pct(recentAbsentRate)} — trending the right way.';
  } else if (lateRate >= 0.15) {
    behaviour = Behaviour.occasionallyLate;
    label = 'Occasionally late';
    note = 'Late ${_pct(lateRate)} of days; otherwise reliable.';
  } else {
    behaviour = Behaviour.reliable;
    label = 'Reliable';
    note =
        'Present ${_pct(presentRate)} of tracked days with little lateness.';
  }

  return PersonProfile(
    trackedDays: n,
    presentRate: presentRate,
    lateRate: lateRate,
    absentRate: absentRate,
    currentAbsentStreak: s.current,
    longestAbsentStreak: s.longest,
    recentAbsentRate: recentAbsentRate,
    priorAbsentRate: priorAbsentRate,
    behaviour: behaviour,
    label: label,
    note: note,
    watch: watch,
    rosterReview: false,
  );
}
