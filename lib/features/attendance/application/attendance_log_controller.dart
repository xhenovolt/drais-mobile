import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/attendance/domain/entities/attendance_history.dart';
import 'package:drais/features/attendance/domain/entities/attendance_insights.dart';
import 'package:drais/features/attendance/domain/repositories/attendance_repository.dart';

/// The web logs page's quick date presets.
enum DatePreset {
  /// Today.
  today('Today'),

  /// Yesterday.
  yesterday('Yesterday'),

  /// Monday to today.
  thisWeek('This week'),

  /// The previous Monday–Sunday.
  lastWeek('Last week'),

  /// The 1st to today.
  thisMonth('This month'),

  /// The whole previous month.
  lastMonth('Last month'),

  /// No date bounds.
  all('All time');

  const DatePreset(this.label);

  /// Menu label.
  final String label;

  /// The `[from, to]` range, computed from [today] (`YYYY-MM-DD`).
  (String?, String?) range(String today) {
    final DateTime t = parseLocalDate(today)!;
    String s(DateTime d) => toLocalDateStr(d);
    final DateTime monday = t.subtract(Duration(days: t.weekday - 1));
    return switch (this) {
      DatePreset.today => (today, today),
      DatePreset.yesterday => (shiftLocalDate(today, -1), shiftLocalDate(today, -1)),
      DatePreset.thisWeek => (s(monday), today),
      DatePreset.lastWeek => (
        s(monday.subtract(const Duration(days: 7))),
        s(monday.subtract(const Duration(days: 1))),
      ),
      DatePreset.thisMonth => (s(DateTime(t.year, t.month)), today),
      DatePreset.lastMonth => (
        s(DateTime(t.year, t.month - 1)),
        s(DateTime(t.year, t.month, 0)),
      ),
      DatePreset.all => (null, null),
    };
  }
}

/// State of the attendance logs screen.
class AttendanceLogState {
  /// Creates log state.
  const AttendanceLogState({
    required this.query,
    this.rows = const <AttendanceHistoryRow>[],
    this.tabCounts = const HistoryTabCounts(),
    this.total = 0,
    this.counts,
    this.offsetMinutes = defaultOffsetMinutes,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.failure,
  });

  /// Initial state: the school-local today, every punch.
  factory AttendanceLogState.initial() {
    final String today = toLocalDateStr();
    return AttendanceLogState(
      query: AttendanceHistoryQuery(dateFrom: today, dateTo: today),
      isLoading: true,
    );
  }

  /// The active filters.
  final AttendanceHistoryQuery query;

  /// Loaded rows across every fetched page.
  final List<AttendanceHistoryRow> rows;

  /// Tab badge counts.
  final HistoryTabCounts tabCounts;

  /// Rows matching the filters, across all pages.
  final int total;

  /// Present / late / absent for the day, when the range is one day.
  final DashboardAttendanceCounts? counts;

  /// The school's UTC offset, for showing punch times as school time.
  final int offsetMinutes;

  /// Whether a first load or a filter change is in flight.
  final bool isLoading;

  /// Whether a page append is in flight.
  final bool isLoadingMore;

  /// The last failure, if any.
  final Failure? failure;

  /// Whether another page exists.
  bool get hasMore => rows.length < total;

  /// Whether the filters genuinely match nothing.
  bool get isEmpty => !isLoading && rows.isEmpty && failure == null;

  /// Whether any loaded device clock is off by more than a minute.
  bool get hasClockConcerns => rows.any(
    (AttendanceHistoryRow r) => (r.clockSkewSeconds ?? 0).abs() >= 60,
  );

  /// Returns a copy. [failure] clears unless supplied.
  AttendanceLogState copyWith({
    AttendanceHistoryQuery? query,
    List<AttendanceHistoryRow>? rows,
    HistoryTabCounts? tabCounts,
    int? total,
    DashboardAttendanceCounts? counts,
    bool clearCounts = false,
    int? offsetMinutes,
    bool? isLoading,
    bool? isLoadingMore,
    Failure? failure,
  }) => AttendanceLogState(
    query: query ?? this.query,
    rows: rows ?? this.rows,
    tabCounts: tabCounts ?? this.tabCounts,
    total: total ?? this.total,
    counts: clearCounts ? null : (counts ?? this.counts),
    offsetMinutes: offsetMinutes ?? this.offsetMinutes,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    failure: failure,
  );
}

/// Drives the attendance logs screen and the home card.
///
/// Read-only by design: DRAIS derives verdicts from raw events through the
/// rule engine. The filters are exactly the web logs page's
/// (`src/app/attendance/logs/page.tsx`).
class AttendanceLogController extends StateNotifier<AttendanceLogState> {
  /// Creates the controller and loads today.
  AttendanceLogController(this._repository)
    : super(AttendanceLogState.initial()) {
    load();
  }

  final AttendanceRepository _repository;

  /// Guards against a slow response overwriting a newer one.
  int _generation = 0;

  /// Loads page 1 of the current query.
  Future<void> load() async {
    final int generation = ++_generation;
    final AttendanceHistoryQuery query = state.query.copyWith(page: 1);
    state = state.copyWith(query: query, isLoading: true);

    // History and counts answer different questions and are fetched together
    // — on a phone link, sequential round trips are the cost that shows.
    final Future<Result<AttendanceHistoryPage>> historyFuture = _repository
        .history(query);
    final Future<Result<DashboardAttendanceCounts>>? countsFuture =
        query.isSingleDay
        ? _repository.dashboardCounts(date: query.dateFrom)
        : null;

    final Result<AttendanceHistoryPage> history = await historyFuture;
    final Result<DashboardAttendanceCounts>? counts = await countsFuture;

    if (!mounted || generation != _generation) return;

    switch (history) {
      case Ok<AttendanceHistoryPage>(:final AttendanceHistoryPage value):
        state = state.copyWith(
          rows: value.rows,
          tabCounts: value.tabCounts,
          total: value.total,
          offsetMinutes: value.offsetMinutes,
          counts: counts?.valueOrNull,
          clearCounts: counts?.valueOrNull == null,
          isLoading: false,
        );
      case Err<AttendanceHistoryPage>(:final Failure failure):
        state = state.copyWith(isLoading: false, failure: failure);
    }
  }

  /// Appends the next page.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;

    final int generation = _generation;
    final AttendanceHistoryQuery next = state.query.copyWith(
      page: state.query.page + 1,
    );
    state = state.copyWith(isLoadingMore: true);
    final Result<AttendanceHistoryPage> result = await _repository.history(
      next,
    );

    if (!mounted || generation != _generation) return;

    switch (result) {
      case Ok<AttendanceHistoryPage>(:final AttendanceHistoryPage value):
        state = state.copyWith(
          query: next,
          rows: <AttendanceHistoryRow>[...state.rows, ...value.rows],
          total: value.total,
          isLoadingMore: false,
        );
      case Err<AttendanceHistoryPage>(:final Failure failure):
        // A failed page keeps what is already on screen.
        state = state.copyWith(isLoadingMore: false, failure: failure);
    }
  }

  Future<void> _apply(AttendanceHistoryQuery query) async {
    state = state.copyWith(query: query);
    await load();
  }

  /// Switches tab.
  Future<void> setTab(HistoryTab tab) async {
    if (tab == state.query.tab) return;
    await _apply(state.query.copyWith(tab: tab));
  }

  /// Sets an explicit range; nulls mean unbounded.
  Future<void> setRange(String? from, String? to) => _apply(
    (from == null && to == null)
        ? state.query.copyWith(clearDates: true)
        : state.query.copyWith(dateFrom: from, dateTo: to),
  );

  /// Applies a quick preset.
  Future<void> applyPreset(DatePreset preset) {
    final (String?, String?) r = preset.range(toLocalDateStr());
    return setRange(r.$1, r.$2);
  }

  /// Steps a single-day range by [days]; widens nothing else.
  Future<void> shiftDay(int days) {
    final String base = state.query.dateFrom ?? toLocalDateStr();
    final String day = shiftLocalDate(base, days);
    return setRange(day, day);
  }

  /// Jumps to the school-local today.
  Future<void> goToToday() => applyPreset(DatePreset.today);

  /// Name / PIN search.
  Future<void> setSearch(String? search) async {
    final String? normalised = (search == null || search.trim().isEmpty)
        ? null
        : search.trim();
    if (normalised == state.query.search) return;
    await _apply(
      normalised == null
          ? state.query.copyWith(clearSearch: true)
          : state.query.copyWith(search: normalised),
    );
  }

  /// Arrival-status quick filter.
  Future<void> setDerived(DerivedFilter derived) =>
      _apply(state.query.copyWith(derived: derived));

  /// Intra-day window.
  Future<void> setTimeframe(HistoryTimeframe timeframe) =>
      _apply(state.query.copyWith(timeframe: timeframe));

  /// Gender filter; null clears.
  Future<void> setGender(String? gender) => _apply(
    gender == null
        ? state.query.copyWith(clearGender: true)
        : state.query.copyWith(gender: gender),
  );

  /// Residence filter; null clears.
  Future<void> setResidence(String? residence) => _apply(
    residence == null
        ? state.query.copyWith(clearResidence: true)
        : state.query.copyWith(residence: residence),
  );

  /// Class filter; null clears.
  Future<void> setClass(int? classId) => _apply(
    classId == null
        ? state.query.copyWith(clearClass: true)
        : state.query.copyWith(classId: classId),
  );

  /// Sort column and direction.
  Future<void> setSort(HistorySort sort, {required bool ascending}) =>
      _apply(state.query.copyWith(sort: sort, ascending: ascending));

  /// Clears every filter except tab, dates and search.
  Future<void> clearFilters() => _apply(
    state.query.copyWith(
      timeframe: HistoryTimeframe.all,
      derived: DerivedFilter.none,
      clearClass: true,
      clearGender: true,
      clearResidence: true,
    ),
  );
}
