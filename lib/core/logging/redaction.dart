/// Removes credentials and personal data from anything about to be logged.
///
/// Applied unconditionally — in development as well as production. Redaction
/// that can be switched off gets switched off, and then a debug build's log,
/// a screenshot, or a bug report carries a live `drais_session` value. That
/// cookie is a bearer credential: whoever holds it is the user for seven days.
///
/// The rule is deliberately blunt: **if a key looks sensitive, the value never
/// appears.** False positives cost a little debuggability; false negatives
/// cost a tenant's data.
abstract final class Redaction {
  /// The placeholder substituted for any redacted value.
  static const String mask = '***';

  /// Map keys whose values are never logged, matched case-insensitively as
  /// substrings so `passwordConfirmation` and `x-session-token` both match.
  static const Set<String> sensitiveKeyFragments = <String>{
    'password',
    'passwd',
    'secret',
    'token',
    'cookie',
    'authorization',
    'auth',
    'session',
    'credential',
    'apikey',
    'api_key',
    'jwt',
    'refresh',
    'signature',
    'otp',
    'pin',
    'fingerprint',
    'biometric',
  };

  /// Keys that merely *look* sensitive but are safe and genuinely useful in a
  /// log. Checked before [sensitiveKeyFragments].
  static const Set<String> allowlistedKeys = <String>{
    'authenticated',
    'auth_state',
    'authstate',
    'session_expired',
    'sessionexpired',
    'requires_reauthentication',
    'token_present',
  };

  /// Cookie name=value pairs anywhere in free text.
  static final RegExp _cookiePattern = RegExp(
    r'(drais_session|drais_control|drais_school_id|drais_role|drais_force_reset)=([^;\s,]+)',
    caseSensitive: false,
  );

  /// `Bearer <token>` / `Basic <token>` in free text.
  static final RegExp _bearerPattern = RegExp(
    r'(bearer|basic)\s+([A-Za-z0-9\-._~+/=]{8,})',
    caseSensitive: false,
  );

  /// `"password": "…"` style JSON fragments in free text.
  static final RegExp _jsonSecretPattern = RegExp(
    r'"(password|token|secret|session_token|sessionToken)"\s*:\s*"[^"]*"',
    caseSensitive: false,
  );

  /// Long hex strings — DRAIS session tokens are 64 hex characters
  /// (`randomBytes(32).toString('hex')` in `/api/auth/login`).
  static final RegExp _hexTokenPattern = RegExp(r'\b[a-f0-9]{32,}\b');

  /// Email addresses. Partially masked rather than removed: knowing *which*
  /// account failed to sign in is often the whole point of the log line.
  static final RegExp _emailPattern = RegExp(
    r'\b([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b',
  );

  /// Scrubs a free-text string.
  static String scrubText(String input) {
    if (input.isEmpty) return input;
    return input
        .replaceAllMapped(_cookiePattern, (Match m) => '${m[1]}=$mask')
        .replaceAllMapped(_bearerPattern, (Match m) => '${m[1]} $mask')
        .replaceAllMapped(_jsonSecretPattern, (Match m) => '"${m[1]}":"$mask"')
        .replaceAll(_hexTokenPattern, mask)
        .replaceAllMapped(_emailPattern, (Match m) => '${m[1]}$mask@${m[2]}');
  }

  /// Scrubs a structured context map, recursing into nested maps and lists.
  static Map<String, Object?> scrubMap(Map<String, Object?> input) {
    final Map<String, Object?> out = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in input.entries) {
      out[entry.key] = isSensitiveKey(entry.key)
          ? mask
          : _scrubValue(entry.value);
    }
    return out;
  }

  /// Whether a map key's value must be masked.
  static bool isSensitiveKey(String key) {
    final String needle = key.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
    if (allowlistedKeys.any(
      (String safe) => needle == safe.replaceAll(RegExp(r'[\s\-_]'), ''),
    )) {
      return false;
    }
    return sensitiveKeyFragments.any(
      (String fragment) =>
          needle.contains(fragment.replaceAll(RegExp(r'[\s\-_]'), '')),
    );
  }

  static Object? _scrubValue(Object? value) {
    if (value == null) return null;
    if (value is String) return scrubText(value);
    if (value is num || value is bool) return value;
    if (value is Map) {
      return scrubMap(
        value.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v)),
      );
    }
    if (value is Iterable) {
      return value.map(_scrubValue).toList(growable: false);
    }
    return scrubText(value.toString());
  }
}
