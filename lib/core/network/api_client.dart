import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/constants/app_version.dart';
import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/network/api_response.dart';
import 'package:drais/core/network/error_mapper.dart';
import 'package:drais/core/network/interceptors/cookie_interceptor.dart';
import 'package:drais/core/network/interceptors/logging_interceptor.dart';
import 'package:drais/core/network/interceptors/retry_interceptor.dart';
import 'package:drais/core/network/interceptors/session_interceptor.dart';
import 'package:drais/core/network/network_info.dart';
import 'package:drais/core/network/pagination.dart';
import 'package:drais/core/storage/cache_store.dart';
import 'package:drais/core/storage/cookie_store.dart';

/// The single HTTP entry point for DRAIS Mobile.
///
/// This is the direct counterpart of `src/lib/apiClient.ts`, whose header
/// says: *"ALL client-side API calls MUST go through apiFetch. Direct fetch()
/// is forbidden."* The same rule holds here — no feature may construct its own
/// `Dio`, and `flutter analyze` plus code review are what enforce it.
///
/// ## What it guarantees
///
/// * The session cookie is attached and refreshed automatically.
/// * Every response is parsed as the DRAIS envelope, including the
///   200-with-`success:false` case the web client also has to handle.
/// * Every failure arrives as a typed [Failure] — never a `DioException`.
/// * Nothing throws: repositories receive a [Result].
/// * Every request carries a correlation id that also reaches the server log.
///
/// ## What it deliberately does not do
///
/// `apiFetch` shows a toast on every mutation. That is right for a web app
/// with one global toast host and wrong for mobile, where the same call may
/// come from a screen, a pull-to-refresh, or a background sync. Presentation
/// decisions belong to the presentation layer, so this client stays silent and
/// the controller decides what the user sees. The divergence is recorded in
/// `docs/PARITY.md`.
class ApiClient {
  /// Creates an API client.
  ///
  /// [onSessionInvalidated] is called when the server reports the session is
  /// dead; the auth controller wires it to a global sign-out.
  ApiClient({
    required this.config,
    required this.baseUrl,
    required CookieStore cookieStore,
    required NetworkInfo networkInfo,
    required AppLogger logger,
    required Future<void> Function(ApiErrorCode code) onSessionInvalidated,
    CacheStore? cacheStore,
    Dio? dio,
  }) : _logger = logger.child('Api'),
       _cache = cacheStore,
       _networkInfo = networkInfo,
       _sessionInterceptor = SessionInterceptor(
         onSessionInvalidated: onSessionInvalidated,
         logger: logger,
       ),
       _dio = dio ?? Dio() {
    _configure(cookieStore, networkInfo, logger);
  }

  final AppConfig config;

  /// Origin of the DRAIS server this client talks to, resolved at runtime by
  /// `ServerController`. Passed in rather than read from [config] because the
  /// address is a device setting, not a build constant — a school may point
  /// the app at its own server without a new APK.
  final String baseUrl;

  final Dio _dio;
  final AppLogger _logger;
  final CacheStore? _cache;
  final NetworkInfo _networkInfo;
  final SessionInterceptor _sessionInterceptor;
  final math.Random _random = math.Random();

  /// Re-arms session handling after a fresh sign-in.
  void resetSessionGuard() => _sessionInterceptor.reset();

  void _configure(
    CookieStore cookieStore,
    NetworkInfo networkInfo,
    AppLogger logger,
  ) {
    _dio.options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.sendTimeout,
      responseType: ResponseType.json,
      contentType: Headers.jsonContentType,
      headers: <String, Object?>{
        HttpHeaderNames.userAgent: AppVersion.userAgent,
        HttpHeaderNames.client: 'mobile',
        HttpHeaderNames.clientVersion: AppVersion.semver,
        'Accept': 'application/json',
      },
      // We inspect every status ourselves — a 402 or 403 carries a body we
      // need, and letting dio throw first would discard it.
      validateStatus: (int? _) => true,
    );

    // Order is load-bearing:
    //   cookies  → the request must be authenticated before anything else
    //   session  → dead-session detection sees the final response
    //   retry    → replays a request that already has its cookie
    //   logging  → outermost, so it observes the true outcome and timing
    _dio.interceptors.addAll(<Interceptor>[
      CookieInterceptor(cookieStore),
      _sessionInterceptor,
      RetryInterceptor(
        maxRetries: config.maxRetries,
        networkInfo: networkInfo,
        logger: logger,
      ),
      LoggingInterceptor(logger: logger, config: config),
    ]);
  }

  // ───────────────────────────────────────────────────────────────────────
  // Verbs
  // ───────────────────────────────────────────────────────────────────────

  /// Performs a `GET`.
  ///
  /// Set [cacheFor] to serve the last successful body when the request fails
  /// for a network reason. Opt-in per call: nothing is cached by default, and
  /// nothing tenant-sensitive should be — see [CacheStore].
  Future<Result<ApiEnvelope<T>>> get<T>(
    String path, {
    Map<String, Object?>? queryParameters,
    T Function(Object json)? fromJson,
    String? dataKey,
    Duration? cacheFor,
    CancelToken? cancelToken,
  }) => _send<T>(
    method: 'GET',
    path: path,
    queryParameters: queryParameters,
    fromJson: fromJson,
    dataKey: dataKey,
    cacheFor: cacheFor,
    cancelToken: cancelToken,
  );

  /// Performs a `POST`.
  Future<Result<ApiEnvelope<T>>> post<T>(
    String path, {
    Object? body,
    Map<String, Object?>? queryParameters,
    T Function(Object json)? fromJson,
    String? dataKey,
    CancelToken? cancelToken,
  }) => _send<T>(
    method: 'POST',
    path: path,
    body: body,
    queryParameters: queryParameters,
    fromJson: fromJson,
    dataKey: dataKey,
    cancelToken: cancelToken,
  );

  /// Performs a `PUT`.
  Future<Result<ApiEnvelope<T>>> put<T>(
    String path, {
    Object? body,
    Map<String, Object?>? queryParameters,
    T Function(Object json)? fromJson,
    String? dataKey,
    CancelToken? cancelToken,
  }) => _send<T>(
    method: 'PUT',
    path: path,
    body: body,
    queryParameters: queryParameters,
    fromJson: fromJson,
    dataKey: dataKey,
    cancelToken: cancelToken,
  );

  /// Performs a `PATCH`.
  Future<Result<ApiEnvelope<T>>> patch<T>(
    String path, {
    Object? body,
    Map<String, Object?>? queryParameters,
    T Function(Object json)? fromJson,
    String? dataKey,
    CancelToken? cancelToken,
  }) => _send<T>(
    method: 'PATCH',
    path: path,
    body: body,
    queryParameters: queryParameters,
    fromJson: fromJson,
    dataKey: dataKey,
    cancelToken: cancelToken,
  );

  /// Performs a `DELETE`.
  Future<Result<ApiEnvelope<T>>> delete<T>(
    String path, {
    Object? body,
    Map<String, Object?>? queryParameters,
    T Function(Object json)? fromJson,
    String? dataKey,
    CancelToken? cancelToken,
  }) => _send<T>(
    method: 'DELETE',
    path: path,
    body: body,
    queryParameters: queryParameters,
    fromJson: fromJson,
    dataKey: dataKey,
    cancelToken: cancelToken,
  );

  /// Fetches one page of a paginated list endpoint.
  Future<Result<PagedResult<T>>> getPage<T>(
    String path, {
    required PageRequest request,
    required T Function(Map<String, Object?> json) itemFromJson,
    CancelToken? cancelToken,
  }) async {
    final Result<ApiEnvelope<void>> result = await _send<void>(
      method: 'GET',
      path: path,
      queryParameters: request.toQueryParameters(),
      cancelToken: cancelToken,
    );

    return result.map(
      (ApiEnvelope<void> envelope) => PagedResult<T>.fromJson(
        envelope.raw,
        itemFromJson: itemFromJson,
        request: request,
      ),
    );
  }

  /// Uploads files as `multipart/form-data`.
  ///
  /// [files] maps a form field name to a local file path. Size is checked
  /// against [AppConfig.maxUploadBytes] before a byte leaves the device —
  /// on a metered connection, failing fast is worth more than the server's
  /// eventual rejection.
  Future<Result<ApiEnvelope<T>>> upload<T>(
    String path, {
    required Map<String, String> files,
    Map<String, Object?> fields = const <String, Object?>{},
    T Function(Object json)? fromJson,
    String? dataKey,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final FormData form = FormData();
      form.fields.addAll(
        fields.entries.map(
          (MapEntry<String, Object?> e) =>
              MapEntry<String, String>(e.key, '${e.value}'),
        ),
      );

      for (final MapEntry<String, String> entry in files.entries) {
        final MultipartFile file = await MultipartFile.fromFile(entry.value);
        if (file.length > config.maxUploadBytes) {
          return Err<ApiEnvelope<T>>(
            ValidationFailure(
              message:
                  'That file is too large. The limit is '
                  '${(config.maxUploadBytes / 1048576).toStringAsFixed(0)} MB.',
              fieldErrors: <String, List<String>>{
                entry.key: <String>['File exceeds the maximum size.'],
              },
              debugContext: <String, Object?>{
                'field': entry.key,
                'bytes': file.length,
                'limit': config.maxUploadBytes,
              },
            ),
          );
        }
        form.files.add(MapEntry<String, MultipartFile>(entry.key, file));
      }

      return await _send<T>(
        method: 'POST',
        path: path,
        body: form,
        fromJson: fromJson,
        dataKey: dataKey,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
        // A multipart body is a single-use stream; a retry would replay an
        // already-consumed stream and send an empty body.
        noRetry: true,
      );
    } on Object catch (e, s) {
      return Err<ApiEnvelope<T>>(
        UnknownFailure(
          message: 'That file could not be read.',
          technicalDetail: e.toString(),
          cause: e,
          stackTrace: s,
        ),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Core
  // ───────────────────────────────────────────────────────────────────────

  Future<Result<ApiEnvelope<T>>> _send<T>({
    required String method,
    required String path,
    Object? body,
    Map<String, Object?>? queryParameters,
    T Function(Object json)? fromJson,
    String? dataKey,
    Duration? cacheFor,
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
    bool noRetry = false,
  }) async {
    final String requestId = _newRequestId();
    final String cacheKey = _cacheKeyFor(path, queryParameters);

    try {
      final Response<Object?> response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: queryParameters?.map(
          (String k, Object? v) => MapEntry<String, dynamic>(k, v),
        ),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        options: Options(
          method: method,
          headers: <String, Object?>{HttpHeaderNames.requestId: requestId},
          extra: <String, Object?>{
            'requestId': requestId,
            if (noRetry) 'noRetry': true,
          },
        ),
      );

      return await _handleResponse<T>(
        response: response,
        fromJson: fromJson,
        dataKey: dataKey,
        cacheFor: cacheFor,
        cacheKey: cacheKey,
        requestId: requestId,
      );
    } on DioException catch (e) {
      final Failure failure = ErrorMapper.fromDioException(e);
      return _recoverOrFail<T>(
        failure: failure,
        fromJson: fromJson,
        dataKey: dataKey,
        cacheKey: cacheKey,
        method: method,
      );
    } on Object catch (e, s) {
      // Nothing should reach here. If it does, it is a bug in this file —
      // log it loudly rather than letting an untyped error escape upward.
      _logger.error(
        'Unhandled transport error.',
        error: e,
        stackTrace: s,
        context: <String, Object?>{'path': path, 'requestId': requestId},
      );
      return Err<ApiEnvelope<T>>(
        UnknownFailure(
          technicalDetail: e.toString(),
          debugContext: <String, Object?>{'path': path, 'requestId': requestId},
          cause: e,
          stackTrace: s,
        ),
      );
    }
  }

  Future<Result<ApiEnvelope<T>>> _handleResponse<T>({
    required Response<Object?> response,
    required String requestId,
    required String cacheKey,
    T Function(Object json)? fromJson,
    String? dataKey,
    Duration? cacheFor,
  }) async {
    final int status = response.statusCode ?? 0;
    final Object? body = response.data;

    if (body is! Map) {
      return Err<ApiEnvelope<T>>(
        ErrorMapper.fromResponse(
          response,
          context: <String, Object?>{'requestId': requestId},
        ),
      );
    }

    final Map<String, Object?> json = body.map(
      (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
    );

    ApiEnvelope<T> envelope;
    try {
      envelope = ApiEnvelope.parse<T>(
        json,
        fromJson: fromJson,
        dataKey: dataKey,
      );
    } on Object catch (e, s) {
      // The envelope was right but the payload did not match our model — a
      // real contract drift between this app and LongTerm. Name it as such;
      // "unknown error" would send the next engineer looking in the wrong
      // place entirely.
      _logger.error(
        'Response payload did not match the expected model.',
        error: e,
        stackTrace: s,
        context: <String, Object?>{
          'path': response.requestOptions.path,
          'requestId': requestId,
        },
      );
      return Err<ApiEnvelope<T>>(
        MalformedResponseFailure(
          message:
              'DRAIS returned data this version of the app does not '
              'understand. Please update the app.',
          technicalDetail: e.toString(),
          statusCode: status,
          debugContext: <String, Object?>{
            'path': response.requestOptions.path,
            'requestId': requestId,
          },
          cause: e,
          stackTrace: s,
        ),
      );
    }

    // `success: false` is a failure at any status, and several routes return
    // exactly that with HTTP 200.
    if (status >= 400 || envelope.isFailure) {
      return Err<ApiEnvelope<T>>(
        ErrorMapper.fromEnvelope(
          ApiEnvelope.parse<void>(json),
          statusCode: status,
          context: <String, Object?>{
            'path': response.requestOptions.path,
            'requestId': requestId,
          },
        ),
      );
    }

    if (cacheFor != null && _cache != null) {
      await _cache.write(cacheKey, json, ttl: cacheFor);
    }

    return Ok<ApiEnvelope<T>>(envelope);
  }

  /// Falls back to cache when a read fails for a network reason.
  ///
  /// Only reads, and only network failures: a 403 must never be papered over
  /// with stale data the user is no longer entitled to see.
  Future<Result<ApiEnvelope<T>>> _recoverOrFail<T>({
    required Failure failure,
    required String cacheKey,
    required String method,
    T Function(Object json)? fromJson,
    String? dataKey,
  }) async {
    final bool isRead = method == 'GET';
    final bool isNetwork =
        failure is NetworkFailure || failure is TimeoutFailure;

    if (isRead && isNetwork && _cache != null) {
      final CachedEntry? cached = _cache.read(cacheKey);
      final Object? body = cached?.body;
      if (body is Map) {
        _logger.info(
          'Serving cached response after a network failure.',
          context: <String, Object?>{
            'key': cacheKey,
            'ageSeconds': cached!.age.inSeconds,
          },
        );
        return Ok<ApiEnvelope<T>>(
          ApiEnvelope.parse<T>(
            body.map(
              (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
            ),
            fromJson: fromJson,
            dataKey: dataKey,
          ),
        );
      }
    }

    // Distinguish "the radio is off" from "the server is unreachable": the
    // remedies differ and the user can act on the first.
    if (failure is NetworkFailure && !await _networkInfo.isConnected) {
      return Err<ApiEnvelope<T>>(
        NetworkFailure(
          message: 'You are offline. Reconnect to continue.',
          technicalDetail: failure.technicalDetail,
          debugContext: failure.debugContext,
          cause: failure.cause,
          stackTrace: failure.stackTrace,
        ),
      );
    }

    return Err<ApiEnvelope<T>>(failure);
  }

  String _cacheKeyFor(String path, Map<String, Object?>? query) {
    if (query == null || query.isEmpty) return path;
    final List<String> pairs =
        query.entries
            .map((MapEntry<String, Object?> e) => '${e.key}=${e.value}')
            .toList()
          ..sort();
    return '$path?${pairs.join('&')}';
  }

  /// A short correlation id, echoed in the `X-Request-Id` header and in every
  /// log line for the request.
  String _newRequestId() {
    const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final String suffix = List<String>.generate(
      8,
      (int _) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
    return 'mob-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$suffix';
  }

  /// Releases the underlying HTTP resources.
  void close() => _dio.close(force: true);
}
