import 'dart:convert';

import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/logging/app_logger.dart';

/// `audit_logs` writes, for direct mode.
///
/// **Ported from `logAudit()` in `src/lib/audit.ts`** (DRAIS LongTerm): the same
/// columns, the same `action` / `action_type` duplication, the same BIGINT
/// coercion of `entity_id`, and the same rule that an audit failure never
/// fails the action it describes.
///
/// One deliberate difference: `source` is `MOBILE`, not the platform default
/// `WEB`. The column's own vocabulary includes `MOBILE`, and an audit trail
/// that attributed phone actions to the web app would be wrong about the one
/// thing it exists to record.
class AuditLog {
  /// Creates an audit writer.
  AuditLog({required DraisDatabase database, required AppLogger logger})
    : _db = database,
      _logger = logger.child('Audit');

  final DraisDatabase _db;
  final AppLogger _logger;

  /// Writes one entry. Never throws.
  Future<void> write({
    required int schoolId,
    required int? userId,
    required String action,
    String entityType = 'system',
    Object? entityId,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    // entity_id is BIGINT: numbers and all-digit strings pass, anything else
    // becomes null (the readable id stays in `details`).
    final int? entityIdNum = switch (entityId) {
      final int n => n,
      final String s when RegExp(r'^\d+$').hasMatch(s) => int.parse(s),
      _ => null,
    };

    try {
      await _db.execute(
        '''
        INSERT INTO audit_logs
          (school_id, user_id, action, action_type, entity_type, entity_id, details, ip_address, user_agent, source)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          schoolId,
          userId,
          action,
          action,
          entityType,
          entityIdNum,
          jsonEncode(details),
          null,
          'DRAIS Mobile (direct)',
          'MOBILE',
        ],
      );
    } on Failure catch (failure) {
      _logger.warn(
        'Failed to write audit log.',
        context: <String, Object?>{
          'action': action,
          'reason': failure.technicalDetail,
        },
      );
    }
  }
}
