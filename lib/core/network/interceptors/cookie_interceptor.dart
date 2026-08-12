import 'package:dio/dio.dart';

import 'package:drais/core/storage/cookie_store.dart';

/// Attaches the DRAIS session cookie to every request and captures the
/// cookies the server sets in reply.
///
/// This is the mobile equivalent of the browser's cookie handling, which
/// `apiClient.ts` gets for free via `credentials: 'include'`. A native HTTP
/// client has no cookie jar, so authentication would silently not happen
/// without this interceptor — every request would look anonymous and every
/// protected route would return 401.
///
/// Order matters: this must run **before** the logging interceptor so that
/// the outgoing `Cookie` header exists to be redacted, and before the retry
/// interceptor so a retried request still carries the session.
class CookieInterceptor extends Interceptor {
  /// Creates a cookie interceptor over [cookieStore].
  CookieInterceptor(this.cookieStore);

  /// The persistent jar.
  final CookieStore cookieStore;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final String? cookies = cookieStore.headerFor(options.path);
    if (cookies != null && cookies.isNotEmpty) {
      options.headers['Cookie'] = cookies;
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) async {
    await _captureCookies(response);
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Error responses set cookies too — `/api/auth/logout` clears them while
    // returning 500 in its own failure path, and a 402 subscription rejection
    // still carries the session. Dropping those would leave a stale jar.
    final Response<Object?>? response = err.response;
    if (response != null) await _captureCookies(response);
    handler.next(err);
  }

  Future<void> _captureCookies(Response<Object?> response) async {
    final List<String>? setCookie =
        response.headers.map[HttpHeaderNames.setCookie];
    if (setCookie == null || setCookie.isEmpty) return;
    await cookieStore.saveFromSetCookieHeaders(setCookie);
  }
}

/// Header names used by the transport layer.
abstract final class HttpHeaderNames {
  /// Response header carrying cookies to store. Lowercase — `dio` normalises
  /// response header keys to lowercase, and a capitalised lookup silently
  /// misses.
  static const String setCookie = 'set-cookie';

  /// Request header carrying stored cookies.
  static const String cookie = 'Cookie';

  /// Identifies the client build to the server's audit trail.
  static const String userAgent = 'User-Agent';

  /// Correlates a mobile log line with a server log line.
  static const String requestId = 'X-Request-Id';

  /// Names the client surface (`mobile`), so server-side analytics can tell
  /// mobile traffic from web without parsing the User-Agent.
  static const String client = 'X-DRAIS-Client';

  /// The client's semantic version, for future minimum-version enforcement.
  static const String clientVersion = 'X-DRAIS-Client-Version';
}
