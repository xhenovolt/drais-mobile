import 'package:drais/core/error/result.dart';
import 'package:drais/features/attendance/domain/entities/attendance_log_entry.dart';

/// Which people a query covers.
enum AttendanceAudience {
  /// Everyone.
  all('all', 'Everyone'),

  /// Learners only.
  students('student', 'Students'),

  /// Staff only.
  staff('staff', 'Staff');

  const AttendanceAudience(this.wireValue, this.label);

  /// The `role_type` value, or `all`.
  final String wireValue;

  /// Label for the filter control.
  final String label;

  /// Whether this narrows the query.
  bool get isFiltered => this != AttendanceAudience.all;
}

/// A query against the attendance log.
class AttendanceLogQuery {
  /// Creates a log query.
  const AttendanceLogQuery({
    required this.date,
    this.audience = AttendanceAudience.all,
    this.search,
    this.onlyNeedingAttention = false,
    this.limit = 100,
    this.offset = 0,
  });

  /// School-local date, `YYYY-MM-DD`.
  ///
  /// Always produced by `toLocalDateStr` or `schoolLocalToday`, never by
  /// formatting a UTC instant — see `core/datetime/local_date.dart`.
  final String date;

  /// Which people to include.
  final AttendanceAudience audience;

  /// Free-text match against the display name.
  final String? search;

  /// Restrict to rows an operator should look at: unmatched identities,
  /// suspect clocks, provisional verdicts.
  final bool onlyNeedingAttention;

  /// Page size.
  final int limit;

  /// Page offset.
  final int offset;

  /// The next page, preserving filters.
  AttendanceLogQuery nextPage() => copyWith(offset: offset + limit);

  /// Returns a copy with the given overrides.
  AttendanceLogQuery copyWith({
    String? date,
    AttendanceAudience? audience,
    String? search,
    bool? onlyNeedingAttention,
    int? limit,
    int? offset,
  }) => AttendanceLogQuery(
    date: date ?? this.date,
    audience: audience ?? this.audience,
    search: search ?? this.search,
    onlyNeedingAttention: onlyNeedingAttention ?? this.onlyNeedingAttention,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
  );
}

/// Counts for a day, as the engine derived them.
class AttendanceDaySummary {
  /// Creates a day summary.
  const AttendanceDaySummary({
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.halfDay = 0,
    this.other = 0,
    this.punches = 0,
    this.unmatchedPunches = 0,
  });

  /// Marked present.
  final int present;

  /// Marked late.
  final int late;

  /// Marked absent.
  final int absent;

  /// Half days.
  final int halfDay;

  /// Weekend, holiday, early leave.
  final int other;

  /// Raw punches recorded, which is **not** the same as people — one person
  /// punching in and out produces two.
  final int punches;

  /// Punches DRAIS could not attach to a person.
  final int unmatchedPunches;

  /// People with a verdict of any kind.
  int get accountedFor => present + late + absent + halfDay + other;

  /// People who actually turned up.
  int get attended => present + late + halfDay;

  /// Whether anything has been recorded at all.
  bool get isEmpty => accountedFor == 0 && punches == 0;
}

/// Reads the attendance log and its daily summary.
///
/// ## Read-only, deliberately
///
/// There is no marking method here. In DRAIS a punch is written through
/// `recordRawEvent`, and the day's verdict is *derived* by the rule evaluator
/// — around 5,000 lines of pure decision logic plus five device-clock
/// policies. A client writing `attendance_records` directly would be
/// fabricating engine output.
///
/// Marking will be added as a separate, explicit capability once the
/// provisional-record story is settled. Until then this interface can only
/// tell you what happened, which is what the screen actually needs.
abstract interface class AttendanceRepository {
  /// Returns log entries matching [query], newest first.
  Future<Result<List<AttendanceLogEntry>>> logEntries(AttendanceLogQuery query);

  /// Returns the derived counts for a day.
  Future<Result<AttendanceDaySummary>> daySummary({
    required String date,
    AttendanceAudience audience = AttendanceAudience.all,
  });

  /// Daily verdict counts over the last [days], newest first.
  Future<Result<List<AttendanceTrendDay>>> trend({
    int days = 14,
    AttendanceAudience audience = AttendanceAudience.students,
  });

  /// Punches DRAIS could not attach to a person, newest first.
  Future<Result<List<UnmatchedPunch>>> unmatchedPunches({int limit = 100});
}

/// One day in an attendance trend.
class AttendanceTrendDay {
  /// Creates a trend day.
  const AttendanceTrendDay({
    required this.date,
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.halfDay = 0,
    this.other = 0,
  });

  /// School-local date.
  final DateTime date;

  /// Marked present.
  final int present;

  /// Marked late.
  final int late;

  /// Marked absent.
  final int absent;

  /// Half days.
  final int halfDay;

  /// Weekend, holiday, early leave.
  final int other;

  /// Everyone with a verdict.
  int get total => present + late + absent + halfDay + other;

  /// Everyone who turned up.
  int get attended => present + late + halfDay;

  /// Attendance rate, or null when there is nothing to divide by.
  double? get rate {
    final int counted = present + late + absent + halfDay;
    return counted == 0 ? null : attended / counted;
  }

  /// Whether every single arrival was classed the same way.
  ///
  /// ## Mobile-only — this is not in LongTerm
  ///
  /// Unlike everything else in this layer, this heuristic has no counterpart
  /// in the web app and its threshold was chosen here, not transcribed. It is
  /// kept because the reasoning holds: real attendance is a mix, so a day
  /// where **everyone** is late — or everyone exactly on time — is almost
  /// never behaviour. It is a device clock that has drifted, or a shift whose
  /// start time does not match reality. One of those is a conversation with
  /// learners and the other is a fix in the settings, and a trend chart that
  /// does not distinguish them sends people to the wrong place.
  ///
  /// It is a *hint on a chart*, never a verdict: nothing derived from it is
  /// written back, and no number an operator reports upward depends on it.
  /// The authoritative signal for the same problem is the Attendance Health
  /// Score's `time` and `device_rep` checks, which are transcribed from the
  /// platform — see `features/timehealth/domain/health_report.dart`.
  ///
  /// If LongTerm grows an equivalent, delete this and port that instead.
  bool get isUniform {
    final int arrivals = present + late;
    // Below ten, a uniform day is unremarkable — a small school on a quiet day.
    if (arrivals < 10) return false;
    return present == 0 || late == 0;
  }

  /// What the uniformity looks like, for the explanation.
  String? get uniformLabel {
    if (!isUniform) return null;
    return late == 0 ? 'everyone on time' : 'everyone late';
  }
}

/// A punch DRAIS could not attach to a person.
///
/// The event is kept regardless — that is the point of an append-only log. An
/// operator can claim it later and the day is recomputed, which is only
/// possible because the raw event was never discarded.
class UnmatchedPunch {
  /// Creates an unmatched punch.
  const UnmatchedPunch({
    required this.id,
    required this.punchAt,
    required this.source,
    this.displayName,
    this.resolutionPath,
  });

  /// `attendance_raw_events.id`.
  final int id;

  /// When it happened.
  final DateTime punchAt;

  /// Which device or process produced it.
  final String source;

  /// The label the device supplied, when it supplied one.
  ///
  /// Often a real name typed into the device by whoever enrolled the finger —
  /// which is exactly the string needed to work out who this is.
  final String? displayName;

  /// How resolution was attempted, e.g. `unresolved`.
  final String? resolutionPath;

  /// Whether there is a name to go on.
  bool get hasNameHint => displayName != null && displayName!.trim().isNotEmpty;
}
