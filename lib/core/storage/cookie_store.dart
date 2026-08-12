import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:drais/core/constants/storage_keys.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/storage/secure_store.dart';

/// A single cookie issued by the DRAIS backend.
///
/// Only the attributes DRAIS actually sets are modelled: `Max-Age`, `Path`,
/// `HttpOnly`, `Secure`, `SameSite`. Domain is not modelled because the app
/// talks to exactly one origin per build ([AppConfig.apiBaseUrl]) and storing
/// a domain we never vary would invite cross-origin bugs.
class DraisCookie {
  /// Creates a cookie.
  const DraisCookie({
    required this.name,
    required this.value,
    this.path = '/',
    this.expiresAt,
    this.httpOnly = false,
    this.secure = false,
  });

  /// Restores a cookie from its persisted JSON form.
  factory DraisCookie.fromJson(Map<String, Object?> json) => DraisCookie(
    name: json['name']! as String,
    value: json['value']! as String,
    path: json['path'] as String? ?? '/',
    expiresAt: json['expiresAt'] == null
        ? null
        : DateTime.tryParse(json['expiresAt']! as String),
    httpOnly: json['httpOnly'] as bool? ?? false,
    secure: json['secure'] as bool? ?? false,
  );

  /// Cookie name, e.g. `drais_session`.
  final String name;

  /// Cookie value. For `drais_session` this is a 64-character hex bearer
  /// token — treat it as a password.
  final String value;

  /// Path scope. DRAIS sets `/` for every auth cookie.
  final String path;

  /// Absolute expiry derived from `Max-Age` at the time of receipt.
  final DateTime? expiresAt;

  /// Whether the server marked it `HttpOnly`. Irrelevant to a native client,
  /// retained so the persisted jar round-trips faithfully.
  final bool httpOnly;

  /// Whether the server marked it `Secure`.
  final bool secure;

  /// Whether the cookie has passed its expiry.
  bool get isExpired {
    final DateTime? at = expiresAt;
    return at != null && at.isBefore(DateTime.now().toUtc());
  }

  /// The `name=value` form sent in a `Cookie` request header.
  String get header => '$name=$value';

  /// Serialises to the persisted JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
    'path': path,
    'expiresAt': expiresAt?.toIso8601String(),
    'httpOnly': httpOnly,
    'secure': secure,
  };

  @override
  String toString() => 'DraisCookie($name, expires: $expiresAt)';
}

/// Persistent cookie jar for the DRAIS school-auth domain.
///
/// ## Why a cookie jar and not a token store
///
/// DRAIS LongTerm authenticates with an opaque **server-side session** keyed by
/// an `HttpOnly` cookie (`drais_session`), written by `/api/auth/login` and
/// validated by `getSessionSchoolId()` against the `sessions` table. There is
/// no JWT, no bearer header, and no refresh endpoint anywhere in the school
/// auth path — the `JWT_SECRET` and `REFRESH_SECRET` variables in `.env` are
/// vestigial.
///
/// The brief said not to redesign authentication unless absolutely necessary,
/// and it is not necessary: a native client can hold cookies perfectly well.
/// So the mobile app is a cookie client. Adding a bearer-token endpoint purely
/// for mobile would fork the auth model across surfaces — precisely the
/// divergence this project exists to prevent.
///
/// See `docs/adr/M0002-cookie-session-parity.md` for the full argument and the
/// conditions under which we would revisit it.
///
/// ## Why not `package:cookie_jar`
///
/// `PersistCookieJar` writes cookies to plain files in the app's documents
/// directory. `drais_session` is a seven-day bearer credential; it belongs in
/// the keystore. This jar is small, holds one origin, and persists through
/// [SecureStore].
class CookieStore {
  /// Creates a cookie store.
  CookieStore({required SecureStore secureStore, required AppLogger logger})
    : _secure = secureStore,
      _logger = logger.child('Cookies');

  final SecureStore _secure;
  final AppLogger _logger;

  /// In-memory jar, keyed by cookie name. Loaded once at boot by [load].
  final Map<String, DraisCookie> _jar = <String, DraisCookie>{};

  bool _loaded = false;

  /// Cookie names that carry the school session. Used to decide whether the
  /// app currently has anything worth trying a session restore with.
  static const Set<String> sessionCookieNames = <String>{
    'drais_session',
    'drais_school_id',
    'drais_role',
    'drais_force_reset',
  };

  /// Whether a (non-expired) session cookie is held.
  bool get hasSession {
    final DraisCookie? session = _jar['drais_session'];
    return session != null && !session.isExpired && session.value.isNotEmpty;
  }

  /// The school id the server attached at login, when present.
  ///
  /// Read-only convenience for diagnostics. **Never send this as a request
  /// parameter** — the server derives `school_id` from the session and
  /// ignores client-supplied values by design (`src/lib/auth.ts`). Trusting a
  /// client-supplied school id is the exact failure ADR-0008 is built to make
  /// impossible.
  int? get schoolIdHint => int.tryParse(_jar['drais_school_id']?.value ?? '');

  /// Loads the persisted jar. Idempotent; call once during bootstrap.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final String? raw = await _secure.read(SecureStorageKeys.sessionCookies);
    if (raw == null || raw.isEmpty) return;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('Cookie jar is not a JSON list.');
      }
      for (final Object? entry in decoded) {
        if (entry is! Map) continue;
        final DraisCookie cookie = DraisCookie.fromJson(
          entry.map(
            (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
          ),
        );
        if (!cookie.isExpired) _jar[cookie.name] = cookie;
      }
      _logger.debug(
        'Cookie jar loaded.',
        context: <String, Object?>{'count': _jar.length},
      );
    } on Object catch (e) {
      // A corrupt jar must not brick the app; the user signs in again.
      _logger.warn(
        'Cookie jar unreadable; discarding.',
        context: <String, Object?>{'reason': e.runtimeType},
      );
      _jar.clear();
      await _secure.delete(SecureStorageKeys.sessionCookies);
    }
  }

  /// The `Cookie` header value for [path], or null when nothing applies.
  String? headerFor(String path) {
    _evictExpired();
    final Iterable<DraisCookie> applicable = _jar.values.where(
      (DraisCookie c) => path.startsWith(c.path),
    );
    if (applicable.isEmpty) return null;
    return applicable.map((DraisCookie c) => c.header).join('; ');
  }

  /// Records the cookies from a response's `Set-Cookie` headers and persists
  /// the jar.
  ///
  /// An empty value means the server is clearing that cookie — `/api/auth/logout`
  /// does exactly this — so the entry is removed rather than stored blank.
  Future<void> saveFromSetCookieHeaders(List<String> headers) async {
    if (headers.isEmpty) return;
    bool changed = false;

    for (final String header in headers) {
      final DraisCookie? cookie = _parseSetCookie(header);
      if (cookie == null) continue;

      if (cookie.value.isEmpty || cookie.isExpired) {
        changed = _jar.remove(cookie.name) != null || changed;
      } else {
        _jar[cookie.name] = cookie;
        changed = true;
      }
    }

    if (changed) await _persist();
  }

  /// Drops every cookie and erases the persisted jar.
  Future<void> clear() async {
    _jar.clear();
    await _secure.delete(SecureStorageKeys.sessionCookies);
    _logger.info('Cookie jar cleared.');
  }

  Future<void> _persist() async {
    final List<Map<String, Object?>> payload = _jar.values
        .map((DraisCookie c) => c.toJson())
        .toList(growable: false);
    await _secure.write(SecureStorageKeys.sessionCookies, jsonEncode(payload));
  }

  void _evictExpired() {
    final List<String> dead = _jar.entries
        .where((MapEntry<String, DraisCookie> e) => e.value.isExpired)
        .map((MapEntry<String, DraisCookie> e) => e.key)
        .toList(growable: false);
    for (final String name in dead) {
      _jar.remove(name);
    }
  }

  /// Parses one `Set-Cookie` header.
  ///
  /// Returns null for anything unparseable rather than throwing: a stray
  /// header from a proxy must not break a request that otherwise succeeded.
  static DraisCookie? _parseSetCookie(String header) {
    final List<String> parts = header.split(';');
    if (parts.isEmpty) return null;

    final int eq = parts.first.indexOf('=');
    if (eq <= 0) return null;

    final String name = parts.first.substring(0, eq).trim();
    final String value = parts.first.substring(eq + 1).trim();
    if (name.isEmpty) return null;

    String path = '/';
    DateTime? expiresAt;
    bool httpOnly = false;
    bool secure = false;

    for (final String attribute in parts.skip(1)) {
      final String attr = attribute.trim();
      final String lower = attr.toLowerCase();

      if (lower == 'httponly') {
        httpOnly = true;
      } else if (lower == 'secure') {
        secure = true;
      } else if (lower.startsWith('path=')) {
        path = attr.substring(5).trim();
        if (path.isEmpty) path = '/';
      } else if (lower.startsWith('max-age=')) {
        // DRAIS sets Max-Age (7 days at login, 0 at logout). It takes
        // precedence over Expires per RFC 6265, and is what we rely on.
        final int? seconds = int.tryParse(attr.substring(8).trim());
        if (seconds != null) {
          expiresAt = DateTime.now().toUtc().add(Duration(seconds: seconds));
        }
      } else if (lower.startsWith('expires=') && expiresAt == null) {
        expiresAt = _parseHttpDate(attr.substring(8).trim());
      }
    }

    return DraisCookie(
      name: name,
      value: value,
      path: path,
      expiresAt: expiresAt,
      httpOnly: httpOnly,
      secure: secure,
    );
  }

  static DateTime? _parseHttpDate(String raw) {
    try {
      return HttpDate.parse(raw).toUtc();
    } on Object {
      return DateTime.tryParse(raw)?.toUtc();
    }
  }
}
