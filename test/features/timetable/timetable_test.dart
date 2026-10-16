import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/timetable/domain/timetable.dart';

void main() {
  test('days are the web grid\'s Monday–Friday, numbered 1–5', () {
    expect(
      timetableDays.map((({int value, String label, String short}) d) => d.value),
      <int>[1, 2, 3, 4, 5],
    );
    expect(timetableDays.first.label, 'Monday');
  });

  test('period time ranges trim seconds and tolerate blanks', () {
    expect(
      const TimetablePeriod(
        id: 1,
        name: 'P1',
        order: 1,
        startTime: '08:00:00',
        endTime: '08:40:00',
      ).timeRange,
      '08:00–08:40',
    );
    expect(const TimetablePeriod(id: 2, name: 'P2', order: 2).timeRange, '');
  });

  test('a lesson is found by day and period', () {
    const TimetableView v = TimetableView(
      metadata: TimetableMetadata(
        classes: <TimetableOption>[],
        streams: <TimetableOption>[],
        periods: <TimetablePeriod>[],
      ),
      entries: <TimetableEntry>[
        TimetableEntry(id: 1, dayOfWeek: 2, periodId: 7, classId: 1, subjectId: 3),
      ],
    );
    expect(v.at(2, 7)?.id, 1);
    expect(v.at(1, 7), isNull);
    expect(v.cachedAt, isNull);
  });
}
