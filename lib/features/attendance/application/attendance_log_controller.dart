import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/attendance/domain/entities/attendance_log_entry.dart';
import 'package:drais/features/attendance/domain/repositories/attendance_repository.dart';

/// State of the attendance log screen.
class AttendanceLogState {
  /// Creates log state.
  const AttendanceLogState({
    required this.query,
    this.entries = const <AttendanceLogEntry>[],
    this.summary = const AttendanceDaySummary(),
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.failure,
  });

  /// Initial state for the school-local today.
  factory AttendanceLogState.initial() => AttendanceLogState(
    query: AttendanceLogQuery(date: toLocalDateStr()),
    isLoading: true,
  );

  /// The active filters.
  final AttendanceLogQuery query;

  /// Loaded entries, newest first.
  final List<AttendanceLogEntry> entries;

  /// Derived counts for the day.
  final AttendanceDaySummary summary;

  /// Whether a first load or a filter change is in flight.
  final bool isLoading;

  /// Whether a page append is in flight.
  final bool isLoadingMore;

  /// Whether another page may exist.
  final bool hasMore;

  /// The last failure, if any.
  final Failure? failure;

  /// Whether the day genuinely has nothing, as opposed to not having loaded.
  bool get isEmpty => !isLoading && entries.isEmpty && failure == null;

  /// Rows an operator should look at.
  int get needingAttention =>
      entries.where((AttendanceLogEntry e) => e.needsAttention).length;

  /// Whether any device clock on this day was materially wrong.
  ///
  /// Surfaced at screen level because it changes how every *other* number
  /// should be read: a slow clock makes arrivals look earlier than they were.
  bool get hasClockConcerns =>
      entries.any((AttendanceLogEntry e) => e.hasMeaningfulSkew);

  /// Returns a copy with the given overrides.
  ///
  /// [failure] clears unless supplied — a stale error must not survive a
  /// successful reload.
  AttendanceLogState copyWith({
    AttendanceLogQuery? query,
    List<AttendanceLogEntry>? entries,
    AttendanceDaySummary? summary,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Failure? failure,
  }) => AttendanceLogState(
    query: query ?? this.query,
    entries: entries ?? this.entries,
    summary: summary ?? this.summary,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    failure: failure,
  );
}

/// Drives the attendance log screen.
///
/// Read-only by design: DRAIS derives verdicts from raw events through the
/// rule engine, so there is nothing here that writes. See
/// [AttendanceRepository].
class AttendanceLogController extends StateNotifier<AttendanceLogState> {
  /// Creates the controller and loads today.
  AttendanceLogController(this._repository)
    : super(AttendanceLogState.initial()) {
    load();
  }

  final AttendanceRepository _repository;

  /// Loads the current query from the start.
  Future<void> load() async {
    state = state.copyWith(
      isLoading: true,
      query: state.query.copyWith(offset: 0),
    );

    // Summary and entries answer different questions — counts come from the
    // engine's verdicts, rows from the raw log — so both are fetched, and a
    // failure in one should not blank the other.
    final Result<AttendanceDaySummary> summary = await _repository.daySummary(
      date: state.query.date,
      audience: state.query.audience,
    );
    final Result<List<AttendanceLogEntry>> entries = await _repository
        .logEntries(state.query.copyWith(offset: 0));

    if (!mounted) return;

    switch (entries) {
      case Ok<List<AttendanceLogEntry>>(:final List<AttendanceLogEntry> value):
        state = state.copyWith(
          entries: value,
          summary: summary.valueOrNull ?? const AttendanceDaySummary(),
          isLoading: false,
          hasMore: value.length >= state.query.limit,
        );
      case Err<List<AttendanceLogEntry>>(:final Failure failure):
        state = state.copyWith(isLoading: false, failure: failure);
    }
  }

  /// Appends the next page.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isLoading) return;

    state = state.copyWith(isLoadingMore: true);
    final AttendanceLogQuery next = state.query.nextPage();
    final Result<List<AttendanceLogEntry>> result = await _repository
        .logEntries(next);

    if (!mounted) return;

    switch (result) {
      case Ok<List<AttendanceLogEntry>>(:final List<AttendanceLogEntry> value):
        state = state.copyWith(
          query: next,
          entries: <AttendanceLogEntry>[...state.entries, ...value],
          isLoadingMore: false,
          hasMore: value.length >= next.limit,
        );
      case Err<List<AttendanceLogEntry>>(:final Failure failure):
        // A failed page keeps what is already on screen — losing a teacher's
        // scroll position to report a network blip is a bad trade.
        state = state.copyWith(isLoadingMore: false, failure: failure);
    }
  }

  /// Moves to a specific school-local date.
  Future<void> setDate(String date) async {
    if (date == state.query.date) return;
    state = state.copyWith(query: state.query.copyWith(date: date));
    await load();
  }

  /// Steps the date by [days].
  Future<void> shiftDate(int days) =>
      setDate(shiftLocalDate(state.query.date, days));

  /// Jumps to the school-local today.
  Future<void> goToToday() => setDate(toLocalDateStr());

  /// Filters by audience.
  Future<void> setAudience(AttendanceAudience audience) async {
    if (audience == state.query.audience) return;
    state = state.copyWith(query: state.query.copyWith(audience: audience));
    await load();
  }

  /// Applies a name search.
  Future<void> setSearch(String? search) async {
    final String? normalised = (search == null || search.trim().isEmpty)
        ? null
        : search.trim();
    if (normalised == state.query.search) return;
    state = state.copyWith(
      query: AttendanceLogQuery(
        date: state.query.date,
        audience: state.query.audience,
        search: normalised,
        onlyNeedingAttention: state.query.onlyNeedingAttention,
        limit: state.query.limit,
      ),
    );
    await load();
  }

  /// Toggles the attention-only filter.
  Future<void> toggleAttentionOnly() async {
    state = state.copyWith(
      query: state.query.copyWith(
        onlyNeedingAttention: !state.query.onlyNeedingAttention,
      ),
    );
    await load();
  }
}
