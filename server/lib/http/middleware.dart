import 'package:shelf/shelf.dart';

import 'package:drais_server/http/api_response.dart';

/// Cross-cutting request handling.
abstract final class DraisMiddleware {
  /// Logs each request with method, path, status and duration.
  ///
  /// **Never logs bodies or headers.** A request body carries passwords and a
  /// header carries the session cookie; a log line holding either is a
  /// credential leak with a long tail (backups, log shipping, screenshots).
  /// The correlation id the mobile client sends is echoed so a client-side
  /// failure can be joined to its server-side line.
  static Middleware logging() => (Handler inner) {
        return (Request request) async {
          final Stopwatch stopwatch = Stopwatch()..start();
          final String? requestId = request.headers['x-request-id'];

          final Response response = await inner(request);

          // ignore: avoid_print
          print(
            '[${DateTime.now().toIso8601String()}] '
            '${response.statusCode} ${request.method} /${request.url.path} '
            '(${stopwatch.elapsedMilliseconds}ms)'
            '${requestId == null ? '' : ' req=$requestId'}',
          );

          return requestId == null
              ? response
              : response.change(
                  headers: <String, String>{'x-request-id': requestId},
                );
        };
      };

  /// Converts an unhandled exception into the standard error envelope.
  ///
  /// Two things must both be true: the client always receives the DRAIS
  /// envelope rather than an HTML stack trace, and the detail reaches the
  /// server log rather than the response. Leaking a SQL fragment tells an
  /// attacker about the schema; leaking nothing at all leaves nobody able to
  /// diagnose it. So: generic message out, full detail to the log.
  static Middleware errors() => (Handler inner) {
        return (Request request) async {
          try {
            return await inner(request);
          } on Object catch (error, stackTrace) {
            // ignore: avoid_print
            print(
              '[ERROR] ${request.method} /${request.url.path}: $error\n'
              '$stackTrace',
            );
            return ApiResponse.serverError();
          }
        };
      };

  /// Adds baseline security headers.
  ///
  /// Modest but not pointless: this API serves only JSON, so a browser should
  /// never be sniffing content types or framing a response.
  static Middleware securityHeaders() => (Handler inner) {
        return (Request request) async {
          final Response response = await inner(request);
          return response.change(
            headers: <String, String>{
              'x-content-type-options': 'nosniff',
              'x-frame-options': 'DENY',
              'referrer-policy': 'no-referrer',
            },
          );
        };
      };

  /// CORS for browser clients.
  ///
  /// The Flutter app is not a browser and needs none of this — it is here for
  /// the web client and for local tooling. `Access-Control-Allow-Origin` is
  /// echoed rather than `*` **because credentials are involved**: a wildcard
  /// origin with `allow-credentials` is rejected by browsers, and would be
  /// unsafe if it were not.
  static Middleware cors({List<String> allowedOrigins = const <String>[]}) =>
      (Handler inner) {
        return (Request request) async {
          final String? origin = request.headers['origin'];
          final bool permitted =
              origin != null && allowedOrigins.contains(origin);

          if (request.method == 'OPTIONS') {
            return Response.ok(
              null,
              headers: _corsHeaders(permitted ? origin : null),
            );
          }

          final Response response = await inner(request);
          return permitted
              ? response.change(headers: _corsHeaders(origin))
              : response;
        };
      };

  static Map<String, String> _corsHeaders(String? origin) =>
      <String, String>{
        if (origin != null) 'access-control-allow-origin': origin,
        'access-control-allow-credentials': 'true',
        'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'access-control-allow-headers':
            'content-type, x-request-id, x-drais-client, x-drais-client-version',
      };
}
