/// Pagination primitives matching the DRAIS list-endpoint convention.
///
/// CONTRIBUTING.md states the rule plainly: *"Paginate list endpoints. An
/// unbounded query over a large school will time out or exhaust memory."*
/// LongTerm list routes take `page`/`limit` (some accept `offset`) and return
/// `{ data: [...], total, page, limit }` alongside the standard envelope.
///
/// One backend quirk is worth knowing about even though it never reaches the
/// client: TiDB rejects `LIMIT ?` under the prepared-statement protocol, so
/// `query()` routes those statements to the text protocol (ADR-0010). The
/// symptom, if it ever regresses, is that **only paginated endpoints fail, and
/// only in production** — worth recognising from the mobile side before
/// concluding the client is at fault.
library;

/// A request for one page of a list endpoint.
class PageRequest {
  /// Creates a page request.
  const PageRequest({
    this.page = 1,
    this.limit = 25,
    this.search,
    this.sortBy,
    this.descending = false,
    this.filters = const <String, Object?>{},
  }) : assert(page >= 1, 'DRAIS pages are 1-based.'),
       assert(limit > 0 && limit <= 200, 'limit must be 1..200');

  /// 1-based page number, matching the backend's convention.
  final int page;

  /// Rows per page.
  final int limit;

  /// Free-text search term, passed as `search`.
  final String? search;

  /// Column to sort by, passed as `sortBy`.
  final String? sortBy;

  /// Sort direction, passed as `sortOrder=desc|asc`.
  final bool descending;

  /// Extra endpoint-specific query parameters.
  ///
  /// **Never put `school_id` here.** The server derives it from the session
  /// and ignores client-supplied values; sending one signals a
  /// misunderstanding of the tenant model (ADR-0008).
  final Map<String, Object?> filters;

  /// The next page, preserving every other parameter.
  PageRequest next() => copyWith(page: page + 1);

  /// Returns a copy with the given overrides.
  PageRequest copyWith({
    int? page,
    int? limit,
    String? search,
    String? sortBy,
    bool? descending,
    Map<String, Object?>? filters,
  }) => PageRequest(
    page: page ?? this.page,
    limit: limit ?? this.limit,
    search: search ?? this.search,
    sortBy: sortBy ?? this.sortBy,
    descending: descending ?? this.descending,
    filters: filters ?? this.filters,
  );

  /// Renders the query parameters for a request.
  Map<String, Object?> toQueryParameters() => <String, Object?>{
    'page': page,
    'limit': limit,
    if (search != null && search!.trim().isNotEmpty) 'search': search!.trim(),
    if (sortBy != null) 'sortBy': sortBy,
    if (sortBy != null) 'sortOrder': descending ? 'desc' : 'asc',
    ...filters,
  };
}

/// One page of results plus the metadata needed to fetch the next.
class PagedResult<T> {
  /// Creates a paged result.
  const PagedResult({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
  });

  /// Builds a page from a decoded envelope body.
  ///
  /// Tolerant by necessity: LongTerm list routes are not perfectly uniform.
  /// Rows may sit under `data`, `items` or `results`; the count may be
  /// `total`, `totalCount` or `count`. Where the total is absent it is
  /// inferred, which yields a correct `hasMore` even without server support.
  factory PagedResult.fromJson(
    Map<String, Object?> body, {
    required T Function(Map<String, Object?> json) itemFromJson,
    required PageRequest request,
  }) {
    final Object? rows = body['data'] ?? body['items'] ?? body['results'];
    final List<T> items = rows is List
        ? rows
              .whereType<Map<Object?, Object?>>()
              .map(
                (Map<Object?, Object?> row) => itemFromJson(
                  row.map(
                    (Object? k, Object? v) =>
                        MapEntry<String, Object?>('$k', v),
                  ),
                ),
              )
              .toList(growable: false)
        : const <Never>[];

    final Object? rawTotal =
        body['total'] ?? body['totalCount'] ?? body['count'];
    final int total = rawTotal is num
        ? rawTotal.toInt()
        // No server total: assume this page is the last unless it came back
        // full, which is the standard "one page beyond" inference.
        : (request.page - 1) * request.limit + items.length;

    return PagedResult<T>(
      items: items,
      page: (body['page'] as num?)?.toInt() ?? request.page,
      limit: (body['limit'] as num?)?.toInt() ?? request.limit,
      total: total,
    );
  }

  /// The rows on this page.
  final List<T> items;

  /// 1-based page number this result represents.
  final int page;

  /// Rows requested per page.
  final int limit;

  /// Total rows matching the query across all pages.
  final int total;

  /// Whether another page exists.
  bool get hasMore => page * limit < total;

  /// Total number of pages.
  int get pageCount => limit == 0 ? 0 : (total / limit).ceil();

  /// Whether this page has no rows.
  bool get isEmpty => items.isEmpty;

  /// Maps each row, preserving pagination metadata.
  PagedResult<R> mapItems<R>(R Function(T item) transform) => PagedResult<R>(
    items: items.map(transform).toList(growable: false),
    page: page,
    limit: limit,
    total: total,
  );
}
