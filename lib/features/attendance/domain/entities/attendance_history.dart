/// The attendance punch history, as `GET /api/attendance/history` returns it.
///
/// Mirrors `src/app/api/attendance/history/route.ts` in DRAIS LongTerm: the
/// same tabs, filters, sort keys and row fields, so the logs screen here and
/// the web logs page answer the same question with the same rows.
library;

/// Which slice of the punch history to show.
///
/// Strict semantics, exactly as the route: a punch is a Learner or Staff row
/// only when it is **matched** with that role. Unmatched punches belong to the
/// Unmatched tab alone.
enum HistoryTab {
  /// Every punch.
  all('all', 'All logs'),

  /// Matched learner punches.
  learners('learners', 'Learners'),

  /// Matched staff punches.
  staff('staff', 'Staff'),

  /// Punches with no confirmed person.
  unmatched('unmatched', 'Unmatched');

  const HistoryTab(this.wireValue, this.label);

  /// The route's `tab` value.
  final String wireValue;

  /// Tab label.
  final String label;
}

/// The arrival-status quick filter — the route's `derived` parameter.
enum DerivedFilter {
  /// No filter.
  none('', 'Any arrival'),

  /// `derived_event = 'ARRIVED_LATE'`.
  late('late', 'Late'),

  /// `derived_event = 'ARRIVED_EARLY'`.
  early('early', 'Early'),

  /// `derived_event IN ('ARRIVED','ARRIVED_EARLY')`.
  onTime('ontime', 'On time');

  const DerivedFilter(this.wireValue, this.label);

  /// The route's value.
  final String wireValue;

  /// Chip label.
  final String label;
}

/// Sortable columns — the route's whitelisted `sort` keys.
enum HistorySort {
  /// `ar.punch_at`.
  time('time', 'Time'),

  /// Resolved display name.
  name('name', 'Name'),

  /// Device PIN.
  pin('pin', 'PIN'),

  /// Device serial.
  device('device', 'Device'),

  /// `derived_event`.
  status('status', 'Status'),

  /// `role_type`.
  type('type', 'Type');

  const HistorySort(this.wireValue, this.label);

  /// The route's value.
  final String wireValue;

  /// Menu label.
  final String label;
}

/// An intra-day window — the web page's timeframe presets.
enum HistoryTimeframe {
  /// No window.
  all(null, null, 'All day'),

  /// 05:00–11:59.
  morning('05:00', '11:59', 'Morning'),

  /// 12:00–16:59.
  afternoon('12:00', '16:59', 'Afternoon'),

  /// 17:00–22:59.
  evening('17:00', '22:59', 'Evening');

  const HistoryTimeframe(this.from, this.to, this.label);

  /// `time_from`, school-local `HH:MM`.
  final String? from;

  /// `time_to`, school-local `HH:MM`.
  final String? to;

  /// Chip label.
  final String label;
}

/// A query against the punch history. Every field maps to one route parameter.
class AttendanceHistoryQuery {
  /// Creates a history query.
  const AttendanceHistoryQuery({
    this.tab = HistoryTab.all,
    this.page = 1,
    this.limit = 50,
    this.dateFrom,
    this.dateTo,
    this.timeframe = HistoryTimeframe.all,
    this.deviceSn,
    this.matched,
    this.search,
    this.classId,
    this.streamId,
    this.residence,
    this.gender,
    this.personId,
    this.derived = DerivedFilter.none,
    this.sort = HistorySort.time,
    this.ascending = false,
  });

  /// `tab`.
  final HistoryTab tab;

  /// 1-based page.
  final int page;

  /// Rows per page. The route allows 1–250.
  final int limit;

  /// School-local `YYYY-MM-DD`, inclusive. Null means unbounded.
  final String? dateFrom;

  /// School-local `YYYY-MM-DD`, inclusive. Null means unbounded.
  final String? dateTo;

  /// `time_from` / `time_to`.
  final HistoryTimeframe timeframe;

  /// `device_sn`.
  final String? deviceSn;

  /// `matched` — true, false, or null for either.
  final bool? matched;

  /// `search` — PIN, device label, name.
  final String? search;

  /// `class_id`.
  final int? classId;

  /// `stream_id`.
  final int? streamId;

  /// `residence` — `day` or `boarding`.
  final String? residence;

  /// `gender` — `male` or `female`.
  final String? gender;

  /// `person_id` — drill-down to one person's punches.
  final int? personId;

  /// `derived`.
  final DerivedFilter derived;

  /// `sort`.
  final HistorySort sort;

  /// `dir=asc` when true.
  final bool ascending;

  /// SQL offset for [page].
  int get offset => (page - 1) * limit;

  /// Whether the range is exactly one day — when day counts make sense.
  bool get isSingleDay => dateFrom != null && dateFrom == dateTo;

  /// Whether any filter beyond tab and dates is active.
  bool get hasExtraFilters =>
      timeframe != HistoryTimeframe.all ||
      derived != DerivedFilter.none ||
      classId != null ||
      residence != null ||
      gender != null ||
      deviceSn != null ||
      matched != null;

  /// Returns a copy. Nullable filters are cleared with the `clear*` flags,
  /// because `null` already means "leave unchanged".
  AttendanceHistoryQuery copyWith({
    HistoryTab? tab,
    int? page,
    int? limit,
    String? dateFrom,
    String? dateTo,
    bool clearDates = false,
    HistoryTimeframe? timeframe,
    String? search,
    bool clearSearch = false,
    int? classId,
    bool clearClass = false,
    String? residence,
    bool clearResidence = false,
    String? gender,
    bool clearGender = false,
    int? personId,
    DerivedFilter? derived,
    HistorySort? sort,
    bool? ascending,
  }) => AttendanceHistoryQuery(
    tab: tab ?? this.tab,
    page: page ?? this.page,
    limit: limit ?? this.limit,
    dateFrom: clearDates ? null : (dateFrom ?? this.dateFrom),
    dateTo: clearDates ? null : (dateTo ?? this.dateTo),
    timeframe: timeframe ?? this.timeframe,
    deviceSn: deviceSn,
    matched: matched,
    search: clearSearch ? null : (search ?? this.search),
    classId: clearClass ? null : (classId ?? this.classId),
    streamId: streamId,
    residence: clearResidence ? null : (residence ?? this.residence),
    gender: clearGender ? null : (gender ?? this.gender),
    personId: personId ?? this.personId,
    derived: derived ?? this.derived,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
  );
}

/// The badge counts on each tab, computed under every filter **except** the
/// tab itself — so a badge never advertises rows the filtered list hides.
class HistoryTabCounts {
  /// Creates tab counts.
  const HistoryTabCounts({
    this.all = 0,
    this.learners = 0,
    this.staff = 0,
    this.unmatched = 0,
  });

  /// `tab_counts.all`.
  final int all;

  /// `tab_counts.learners`.
  final int learners;

  /// `tab_counts.staff`.
  final int staff;

  /// `tab_counts.unmatched`.
  final int unmatched;

  /// The count for [tab].
  int of(HistoryTab tab) => switch (tab) {
    HistoryTab.all => all,
    HistoryTab.learners => learners,
    HistoryTab.staff => staff,
    HistoryTab.unmatched => unmatched,
  };
}

/// A confidence band — `bandOf()` in `confidence-scoring.ts`.
enum ConfidenceBand {
  /// ≥ 85.
  high,

  /// 60–84.
  medium,

  /// < 60.
  low,
}

/// One sub-confidence: a 0–100 score, its band, and why.
class Confidence {
  /// Creates a confidence.
  const Confidence({
    required this.score,
    required this.band,
    required this.reason,
  });

  /// 0–100.
  final int score;

  /// The band [score] falls in.
  final ConfidenceBand band;

  /// Operator-facing explanation.
  final String reason;
}

/// Per-record trust — `RecordConfidence` in `confidence-scoring.ts`.
class RecordConfidence {
  /// Creates a record confidence.
  const RecordConfidence({
    required this.overall,
    required this.identity,
    required this.device,
    required this.time,
    required this.policy,
  });

  /// Weighted, gated overall.
  final Confidence overall;

  /// Is this the right person?
  final Confidence identity;

  /// Is the source device healthy?
  final Confidence device;

  /// Is the timestamp believable?
  final Confidence time;

  /// Was a real rule applied?
  final Confidence policy;
}

/// One punch row, with the joins the web logs page shows.
class AttendanceHistoryRow {
  /// Creates a row.
  const AttendanceHistoryRow({
    required this.id,
    required this.checkTime,
    required this.matched,
    required this.isProvisional,
    required this.personType,
    required this.confidence,
    this.deviceSn,
    this.deviceUserId,
    this.verifyType,
    this.ioMode,
    this.derivedEvent,
    this.derivedDetail,
    this.roleType,
    this.personName,
    this.personId,
    this.source,
    this.resolutionPath,
    this.clockSkewSeconds,
    this.deviceName,
    this.deviceLocation,
    this.className,
    this.smsStatus,
    this.firstName,
    this.lastName,
    this.photoUrl,
    this.gender,
    this.admissionNo,
    this.staffPosition,
    this.staffDepartment,
  });

  /// `attendance_raw_events.id`.
  final int id;

  /// `punch_at` — a UTC instant.
  final DateTime checkTime;

  /// Whether the punch resolved to a person.
  final bool matched;

  /// Provisional identity, or unmatched with no person — the route's rule.
  final bool isProvisional;

  /// `role_type`, or `unmatched`.
  final String personType;

  /// Per-record trust.
  final RecordConfidence confidence;

  /// Device serial.
  final String? deviceSn;

  /// PIN on the device.
  final String? deviceUserId;

  /// How the device verified the person (fingerprint, face, card…).
  final String? verifyType;

  /// In/out flag, when the device sent one.
  final int? ioMode;

  /// Engine event, e.g. `ARRIVED_LATE`.
  final String? derivedEvent;

  /// Engine detail, e.g. `Late by 12 min`.
  final String? derivedDetail;

  /// `student` | `staff` | null.
  final String? roleType;

  /// Display name, device label, or directory name — the route's fallback
  /// chain.
  final String? personName;

  /// Resolved person.
  final int? personId;

  /// `zkteco_push`, `manual`, …
  final String? source;

  /// How identity was resolved.
  final String? resolutionPath;

  /// Device clock error in seconds.
  final int? clockSkewSeconds;

  /// Registered device name, or the directory's.
  final String? deviceName;

  /// Where the device is.
  final String? deviceLocation;

  /// Learner's primary active class.
  final String? className;

  /// Latest notification status that day.
  final String? smsStatus;

  /// `people.first_name`.
  final String? firstName;

  /// `people.last_name`.
  final String? lastName;

  /// `people.photo_url`.
  final String? photoUrl;

  /// `people.gender`, as stored.
  final String? gender;

  /// `students.admission_no`.
  final String? admissionNo;

  /// `staff.position`.
  final String? staffPosition;

  /// Staff department name.
  final String? staffDepartment;

  /// Name to show, never empty.
  String get label {
    final String? name = personName?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (deviceUserId != null) return 'PIN $deviceUserId';
    return 'Unidentified';
  }

  /// Initials for an avatar.
  String get initials {
    final List<String> parts = label
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty && !p.startsWith('PIN'))
        .toList();
    if (parts.isEmpty) return '?';
    final String a = parts.first[0];
    final String b = parts.length > 1 ? parts.last[0] : '';
    return '$a$b'.toUpperCase();
  }

  /// The line under the name: class and admission number for a learner,
  /// position and department for staff.
  String? get subtitle {
    final List<String> bits = <String>[
      if (roleType == 'student') ...<String>[
        if (className != null && className!.isNotEmpty) className!,
        if (admissionNo != null && admissionNo!.isNotEmpty) admissionNo!,
      ],
      if (roleType == 'staff') ...<String>[
        if (staffPosition != null && staffPosition!.isNotEmpty) staffPosition!,
        if (staffDepartment != null && staffDepartment!.isNotEmpty)
          staffDepartment!,
      ],
    ];
    return bits.isEmpty ? null : bits.join(' · ');
  }

  /// A short label for [derivedEvent].
  String? get derivedLabel => switch (derivedEvent) {
    'ARRIVED' => 'On time',
    'ARRIVED_LATE' => 'Late',
    'ARRIVED_EARLY' => 'Early',
    'CHECKED_OUT' => 'Checked out',
    'EARLY_DEPARTURE' => 'Left early',
    'OVERTIME_EXIT' => 'Overtime',
    'RETURNED' => 'Returned',
    'STEPPED_OUT' => 'Stepped out',
    null || '' => null,
    final String other => other
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp('^.'), (Match m) => m[0]!.toUpperCase()),
  };

  /// The attendance-status colour key for [derivedEvent].
  String? get derivedStatusKey => switch (derivedEvent) {
    'ARRIVED' || 'ARRIVED_EARLY' || 'CHECKED_OUT' => 'present',
    'ARRIVED_LATE' => 'late',
    'EARLY_DEPARTURE' => 'early_leave',
    _ => null,
  };
}

/// A class, for the class filter — `/api/classes`.
class ClassOption {
  /// Creates a class option.
  const ClassOption({required this.id, required this.name});

  /// `classes.id`.
  final int id;

  /// `classes.name`.
  final String name;
}

/// One page of history.
class AttendanceHistoryPage {
  /// Creates a page.
  const AttendanceHistoryPage({
    required this.rows,
    required this.tabCounts,
    required this.page,
    required this.limit,
    required this.total,
    this.timezone = 'Africa/Kampala',
    this.offsetMinutes = 180,
  });

  /// `data`.
  final List<AttendanceHistoryRow> rows;

  /// `tab_counts`.
  final HistoryTabCounts tabCounts;

  /// `pagination.page`.
  final int page;

  /// `pagination.limit`.
  final int limit;

  /// `pagination.total`.
  final int total;

  /// `presentation.timezone`.
  final String timezone;

  /// The school's UTC offset, for rendering [AttendanceHistoryRow.checkTime].
  final int offsetMinutes;

  /// `pagination.totalPages`.
  int get totalPages => limit == 0 ? 0 : (total / limit).ceil();

  /// Whether another page exists.
  bool get hasMore => page * limit < total;
}
