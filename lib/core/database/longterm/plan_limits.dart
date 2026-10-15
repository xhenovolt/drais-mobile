/// Plan capacity gates, for direct-mode writes that create records.
///
/// Ported from DRAIS LongTerm:
///
/// * [checkCapacity]: `checkCapacity()` / `getLimitState()` in
///   `src/lib/entitlements/limits.ts`;
/// * [enforcePlanLimit]: `enforcePlanLimit()` in
///   `src/lib/control/plan-enforcement.ts`.
///
/// Both **fail open**, exactly as the platform does. An unresolvable plan, a
/// malformed limit, or a failed count never blocks a school; restricting a
/// school is something an operator chooses by assigning it a plan.
///
/// ## The one input a phone cannot see
///
/// `enforcePlanLimit` also consults the server environment variable
/// `ENFORCE_PLAN_LIMITS`. A handset has no server environment, so the global
/// flag reads as **off**, which is its documented default. The per-school
/// override in `school_settings` (`billing.enforce_limits` = `on`/`off`) is
/// read and wins, as on the platform. Recorded in `docs/PARITY.md` §4.
library;

import 'dart:convert';

import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/failure.dart';

/// The platform's metered resources and how each is counted. These
/// predicates must match the Control Center display (platform comment).
const Map<String, String> _countMeters = <String, String>{
  'learners':
      "SELECT COUNT(*) n FROM students WHERE school_id = ? AND deleted_at IS NULL AND status = 'active'",
  'staff':
      "SELECT COUNT(*) n FROM staff WHERE school_id = ? AND deleted_at IS NULL AND status = 'active'",
  'devices':
      "SELECT COUNT(*) n FROM devices WHERE school_id = ? AND deleted_at IS NULL AND status NOT IN ('retired')",
};

const Map<String, String> _labels = <String, String>{
  'learners': 'learners',
  'staff': 'staff members',
  'devices': 'devices',
};

Map<String, Object?>? _parseLimits(Object? raw) {
  if (raw == null) return null;
  try {
    final Object? decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is Map) {
      return decoded.map(
        (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
      );
    }
  } on FormatException {
    // Malformed JSON must not become an accidental lockout.
  }
  return null;
}

/// `checkCapacity()`: the refusal message when [requested] more of [key]
/// would exceed the school's plan, or null to proceed.
Future<String?> checkCapacity(
  DraisDatabase db,
  int schoolId,
  String key, {
  int requested = 1,
}) async {
  if (requested <= 0) return null;

  Map<String, Object?>? limits;
  try {
    final Row? row = await db.queryOne(
      '''
      SELECT p.limits
        FROM schools s
        JOIN subscription_plans p
          ON p.code = s.subscription_plan
         AND p.is_active = TRUE
       WHERE s.id = ?
       LIMIT 1
      ''',
      <Object?>[schoolId],
    );
    limits = _parseLimits(row?['limits']);
  } on Failure {
    limits = null;
  }

  final Object? rawLimit = limits?[key];
  // JavaScript's Number.isFinite(): only a real number is a ceiling.
  if (rawLimit is! num || !rawLimit.isFinite || rawLimit <= 0) return null;
  final int limit = rawLimit.toInt();

  final String? meter = _countMeters[key];
  if (meter == null) return null;
  int used;
  try {
    final Row? r = await db.queryOne(meter, <Object?>[schoolId]);
    used = SqlValue.asInt(r?['n']) ?? 0;
  } on Failure {
    // A failed count must not read as "zero used"; fail open instead.
    return null;
  }

  if (used + requested <= limit) return null;

  final int remaining = (limit - used) < 0 ? 0 : limit - used;
  final String label = _labels[key] ?? key.replaceAll('_', ' ');
  return remaining == 0
      ? 'Your plan allows $limit $label and you have $used. Archive records you no longer need, or upgrade the plan.'
      : 'This would exceed your plan: $remaining of $limit $label remaining, $requested requested.';
}

/// `enforcePlanLimit()`: the refusal reason, or null to proceed.
Future<String?> enforcePlanLimit(
  DraisDatabase db,
  int schoolId,
  String resource, {
  int adding = 1,
}) async {
  try {
    final Row? setting = await db.queryOne(
      "SELECT value_text FROM school_settings WHERE school_id = ? AND key_name = 'billing.enforce_limits' LIMIT 1",
      <Object?>[schoolId],
    );
    // resolveEnforcement(): the override wins; otherwise the global flag,
    // which a device cannot read and therefore treats as its default, off.
    final String? override = SqlValue.asString(setting?['value_text']);
    final bool on = override == 'on';
    if (!on) return null;

    final Row? school = await db.queryOne(
      'SELECT subscription_plan FROM schools WHERE id = ? LIMIT 1',
      <Object?>[schoolId],
    );
    final String? code = SqlValue.asString(school?['subscription_plan']);
    if (code == null || code.isEmpty) return null;

    final Row? plan = await db.queryOne(
      'SELECT limits FROM subscription_plans WHERE code = ? LIMIT 1',
      <Object?>[code],
    );
    if (plan == null) return null;
    final Object? raw = _parseLimits(plan['limits'])?[resource];
    // checkCanAdd(): null or 0 means unlimited.
    if (raw == null || raw == 0) return null;
    final num? cap = raw is num ? raw : num.tryParse('$raw');
    if (cap == null) return null;

    final String? meter = _countMeters[resource];
    if (meter == null) return null;
    final Row? r = await db.queryOne(meter, <Object?>[schoolId]);
    final int current = SqlValue.asInt(r?['n']) ?? 0;

    if (current + adding > cap) {
      return 'Plan limit reached: $current/$raw $resource. Upgrade the plan or contact Xhenvolt.';
    }
    return null;
  } on Failure {
    return null; // Fail open: never block on an enforcement error.
  }
}
