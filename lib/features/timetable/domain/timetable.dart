import 'package:drais/core/error/result.dart';

/// The web grid's days — `DAYS` in `src/components/timetable/TimetableGrid.tsx`.
const List<({int value, String label, String short})> timetableDays =
    <({int value, String label, String short})>[
      (value: 1, label: 'Monday', short: 'Mon'),
      (value: 2, label: 'Tuesday', short: 'Tue'),
      (value: 3, label: 'Wednesday', short: 'Wed'),
      (value: 4, label: 'Thursday', short: 'Thu'),
      (value: 5, label: 'Friday', short: 'Fri'),
    ];

/// One slot in the school day — `timetable_periods`.
class TimetablePeriod {
  /// Creates a period.
  const TimetablePeriod({
    required this.id,
    required this.name,
    required this.order,
    this.shortName,
    this.startTime,
    this.endTime,
    this.isBreak = false,
  });

  /// Row id.
  final int id;

  /// e.g. `Period 1`.
  final String name;

  /// e.g. `P1`.
  final String? shortName;

  /// `HH:MM:SS`.
  final String? startTime;

  /// `HH:MM:SS`.
  final String? endTime;

  /// Position in the day.
  final int order;

  /// A break, lunch or assembly — no lessons.
  final bool isBreak;

  /// `08:00–08:40`.
  String get timeRange {
    String hm(String? t) => (t == null || t.length < 5) ? '' : t.substring(0, 5);
    final String a = hm(startTime);
    final String b = hm(endTime);
    return a.isEmpty && b.isEmpty ? '' : '$a–$b';
  }
}

/// One lesson — `timetable_entries` with its joins.
class TimetableEntry {
  /// Creates an entry.
  const TimetableEntry({
    required this.id,
    required this.dayOfWeek,
    required this.periodId,
    required this.classId,
    required this.subjectId,
    this.streamId,
    this.teacherId,
    this.room,
    this.className,
    this.streamName,
    this.subjectName,
    this.subjectCode,
    this.teacherName,
  });

  /// Row id.
  final int id;

  /// 1 = Monday … 5 = Friday.
  final int dayOfWeek;

  /// The period.
  final int periodId;

  /// The class.
  final int classId;

  /// The stream, when the lesson is for one.
  final int? streamId;

  /// The subject.
  final int subjectId;

  /// `staff.id`.
  final int? teacherId;

  /// Room.
  final String? room;

  /// Class name.
  final String? className;

  /// Stream name.
  final String? streamName;

  /// Subject name.
  final String? subjectName;

  /// Subject code.
  final String? subjectCode;

  /// `first last`, or `Staff <id>` when the teacher has no person record.
  final String? teacherName;
}

/// A pickable class or stream.
class TimetableOption {
  /// Creates an option.
  const TimetableOption({required this.id, required this.label, this.parentId});

  /// Row id.
  final int id;

  /// Name.
  final String label;

  /// A stream's class.
  final int? parentId;
}

/// What the grid needs to draw — `/api/timetable-metadata`'s classes,
/// streams and periods.
class TimetableMetadata {
  /// Creates metadata.
  const TimetableMetadata({
    required this.classes,
    required this.streams,
    required this.periods,
  });

  /// Classes, by level then name.
  final List<TimetableOption> classes;

  /// Streams, each with its class.
  final List<TimetableOption> streams;

  /// Every period, breaks included, in order.
  final List<TimetablePeriod> periods;
}

/// A loaded timetable, and whether it came from the device's cache.
class TimetableView {
  /// Creates a view.
  const TimetableView({
    required this.metadata,
    required this.entries,
    this.cachedAt,
  });

  /// Classes, streams and periods.
  final TimetableMetadata metadata;

  /// Lessons for the selection.
  final List<TimetableEntry> entries;

  /// When the cached copy was stored, if this is one — set only when the
  /// database could not be reached.
  final DateTime? cachedAt;

  /// The lesson at a day and period, if any.
  TimetableEntry? at(int day, int periodId) {
    for (final TimetableEntry e in entries) {
      if (e.dayOfWeek == day && e.periodId == periodId) return e;
    }
    return null;
  }
}

/// The school timetable, read-only.
///
/// | Method | LongTerm source |
/// |---|---|
/// | [load] | `GET /api/timetable-metadata` + `GET /api/timetable-entries` |
/// | [myStaffId] | the session's staff link (`staff.person_id = users.person_id`) |
abstract interface class TimetableRepository {
  /// Metadata and lessons for a class (and optional stream) or a teacher.
  Future<Result<TimetableView>> load({
    int? classId,
    int? streamId,
    int? teacherId,
  });

  /// The signed-in user's `staff.id`, or null when they are not staff.
  Future<Result<int?>> myStaffId();
}
