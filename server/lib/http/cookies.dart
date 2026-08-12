import 'package:shelf/shelf.dart';

/// Session cookie handling, matching the platform's names and attributes.
///
/// The Flutter client stores whatever `Set-Cookie` it receives and replays it,
/// exactly as a browser would. So these names and attributes are part of the
/// contract: change `drais_session` here and every installed app stops being
/// able to sign in.
abstract final class Cookies {
  /// The session cookie. `HttpOnly` — a bearer credential for its lifetime.
  static const String session = 'drais_session';

  /// The signed-in user's school. Readable by design in the web app, where
  /// Edge middleware needs it before any database call.
  ///
  /// **Never trusted as input.** The server derives `school_id` from the
  /// session row on every request; this cookie is a hint for the client, and
  /// a request that supplied its own school id would be ignored.
  static const String schoolId = 'drais_school_id';

  /// Primary role name, for the web middleware's route guards.
  static const String role = 'drais_role';

  /// Set when the user must change their password before continuing.
  static const String forceReset = 'drais_force_reset';

  /// Reads a cookie from a request.
  static String? read(Request request, String name) {
    final String? header = request.headers['cookie'];
    if (header == null || header.isEmpty) return null;

    for (final String part in header.split(';')) {
      final int eq = part.indexOf('=');
      if (eq <= 0) continue;
      if (part.substring(0, eq).trim() == name) {
        return part.substring(eq + 1).trim();
      }
    }
    return null;
  }

  /// Builds a `Set-Cookie` value.
  ///
  /// [secure] must be false for a school server on a plain-HTTP LAN —
  /// a `Secure` cookie over HTTP is silently never returned, which presents
  /// as "login succeeds then immediately logs out".
  static String build(
    String name,
    String value, {
    required int maxAgeSeconds,
    required bool secure,
    bool httpOnly = true,
    String path = '/',
    String sameSite = 'Lax',
  }) {
    final StringBuffer cookie = StringBuffer()
      ..write('$name=$value')
      ..write('; Path=$path')
      ..write('; Max-Age=$maxAgeSeconds')
      ..write('; SameSite=$sameSite');
    if (httpOnly) cookie.write('; HttpOnly');
    if (secure) cookie.write('; Secure');
    return cookie.toString();
  }

  /// Builds a `Set-Cookie` that deletes [name].
  static String clear(String name, {required bool secure, bool httpOnly = true}) =>
      build(
        name,
        '',
        maxAgeSeconds: 0,
        secure: secure,
        httpOnly: httpOnly,
      );

  /// Attaches multiple `Set-Cookie` headers to a response.
  ///
  /// Shelf collapses a repeated header into one comma-joined value, which
  /// breaks cookie parsing (dates contain commas). `headersAll` keeps them as
  /// distinct headers, which is what clients expect.
  static Response withCookies(Response response, List<String> cookies) =>
      response.change(
        headers: <String, List<String>>{
          ...response.headersAll,
          'set-cookie': cookies,
        },
      );
}
