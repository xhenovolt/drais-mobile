import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:drais/core/constants/storage_keys.dart';
import 'package:drais/core/logging/app_logger.dart';

/// One cached API response with the metadata needed to judge its age.
class CachedEntry {
  /// Creates a cache entry.
  const CachedEntry({
    required this.body,
    required this.storedAt,
    required this.ttl,
  });

  /// Restores an entry from its persisted JSON form.
  static CachedEntry? tryFromJson(Map<String, Object?> json) {
    final Object? body = json['body'];
    final String? storedAt = json['storedAt'] as String?;
    final int? ttlSeconds = json['ttlSeconds'] as int?;
    if (body == null || storedAt == null || ttlSeconds == null) return null;

    final DateTime? at = DateTime.tryParse(storedAt);
    if (at == null) return null;

    return CachedEntry(
      body: body,
      storedAt: at,
      ttl: Duration(seconds: ttlSeconds),
    );
  }

  /// The decoded JSON body exactly as the server returned it.
  final Object body;

  /// When it was written, in UTC.
  final DateTime storedAt;

  /// How long it is considered fresh.
  final Duration ttl;

  /// How old the entry is now.
  Duration get age => DateTime.now().toUtc().difference(storedAt);

  /// Whether the entry is still within its TTL.
  bool get isFresh => age < ttl;

  /// Serialises to the persisted JSON form.
  Map<String, Object?> toJson() => <String, Object?>{
    'body': body,
    'storedAt': storedAt.toIso8601String(),
    'ttlSeconds': ttl.inSeconds,
  };
}

/// Read-through cache for GET responses, and the seam offline support grows
/// from.
///
/// ## Scope, deliberately small
///
/// This caches **successful GET response bodies** and nothing else. It is not
/// an offline database and does not queue writes. A school with no connection
/// can therefore *read* what it last loaded; it cannot mark attendance
/// offline and sync later.
///
/// That limitation is intentional at 1.0.0. Offline **writes** need a
/// conflict-resolution model, which ADR-0010 in LongTerm records as an
/// unsolved design problem rather than an implementation gap — the same
/// reasoning applies here, and inventing a mobile-only answer would be exactly
/// the divergence this project is meant to avoid. The upgrade path (a Drift
/// database plus an outbox) is set out in `docs/OFFLINE_STRATEGY.md`.
///
/// ## Storage choice
///
/// `SharedPreferences` is plaintext, so **only non-sensitive reads may be
/// cached**. Callers opt in per request via `RequestOptions.extra['cache']`;
/// nothing is cached by default. Any endpoint returning credentials or another
/// tenant's data must not be cached — the enforcement is the caller's, and
/// the rule is stated in `docs/CODING_STANDARDS.md`.
class CacheStore {
  /// Creates a cache store.
  CacheStore({
    required SharedPreferences preferences,
    required AppLogger logger,
  }) : _prefs = preferences,
       _logger = logger.child('Cache');

  /// Opens the cache over the platform preference store.
  static Future<CacheStore> open(AppLogger logger) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return CacheStore(preferences: prefs, logger: logger);
  }

  final SharedPreferences _prefs;
  final AppLogger _logger;

  /// Default freshness window for a cached read.
  static const Duration defaultTtl = Duration(minutes: 15);

  /// Reads the entry for [requestUri], or null when absent or unreadable.
  ///
  /// An expired entry is returned rather than dropped: it is still the best
  /// thing to render while offline. Callers check [CachedEntry.isFresh] and
  /// decide whether to show a "last updated" notice.
  CachedEntry? read(String requestUri) {
    final String key = CacheKeys.forRequest(requestUri);
    final String? raw = _prefs.getString(key);
    if (raw == null) return null;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return CachedEntry.tryFromJson(
        decoded.map(
          (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
        ),
      );
    } on Object {
      _logger.warn(
        'Discarding unreadable cache entry.',
        context: <String, Object?>{'uri': requestUri},
      );
      _prefs.remove(key).ignore();
      return null;
    }
  }

  /// Stores [body] against [requestUri].
  Future<void> write(
    String requestUri,
    Object body, {
    Duration ttl = defaultTtl,
  }) async {
    final CachedEntry entry = CachedEntry(
      body: body,
      storedAt: DateTime.now().toUtc(),
      ttl: ttl,
    );
    try {
      await _prefs.setString(
        CacheKeys.forRequest(requestUri),
        jsonEncode(entry.toJson()),
      );
    } on Object catch (e) {
      // A cache miss is never fatal — losing a write is acceptable, and
      // failing the user's request because of it would not be.
      _logger.warn(
        'Cache write failed.',
        context: <String, Object?>{'uri': requestUri, 'reason': e.runtimeType},
      );
    }
  }

  /// Removes every cache entry whose key starts with [uriPrefix].
  ///
  /// The mobile counterpart of SWR's `mutate(key)` (ADR-0013): after a write,
  /// invalidate the reads it affects. A missing invalidation is the most
  /// common cause of "stale data" reports that are not bugs.
  Future<void> invalidate(String uriPrefix) async {
    final String prefix = CacheKeys.forRequest(uriPrefix);
    final Iterable<String> victims = _prefs.getKeys().where(
      (String k) => k.startsWith(prefix),
    );
    for (final String key in victims) {
      await _prefs.remove(key);
    }
  }

  /// Empties the cache.
  ///
  /// **Must be called on sign-out.** A cached class list from one bursar's
  /// session that survives into the next user's is a tenant-isolation failure
  /// on the device, even though the server behaved correctly.
  Future<void> clearAll() async {
    final Iterable<String> keys = _prefs
        .getKeys()
        .where((String k) => k.startsWith(CacheKeys.prefix))
        .toList(growable: false);
    for (final String key in keys) {
      await _prefs.remove(key);
    }
    _logger.info(
      'Cache cleared.',
      context: <String, Object?>{'entries': keys.length},
    );
  }
}
