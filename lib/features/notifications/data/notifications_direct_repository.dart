import 'dart:convert';

import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/notifications/domain/notifications.dart';

/// In-app notifications, straight from TiDB — `NotificationService`'s
/// `list`, `getUnreadCount`, `markAsRead` and `archive`
/// (`src/lib/NotificationService.ts`, DRAIS LongTerm), in Dart.
///
/// Scoped as the service scopes it: by the signed-in user's id, plus the
/// school for reads. The socket "notification:updated" event the service
/// emits after a write has no listener on a phone and is not reproduced.
class NotificationsDirectRepository implements NotificationsRepository {
  /// Creates the repository.
  NotificationsDirectRepository({
    required DraisDatabase database,
    required int schoolId,
    required int userId,
  }) : _db = database,
       _schoolId = schoolId,
       _userId = userId;

  final DraisDatabase _db;
  final int _schoolId;
  final int _userId;

  @override
  Future<Result<NotificationPage>> list({
    NotificationFilter filter = NotificationFilter.all,
    String? cursor,
    int limit = 25,
  }) async {
    try {
      final List<Object?> params = <Object?>[_userId, _schoolId];
      final StringBuffer where = StringBuffer(
        'un.user_id = ? AND n.deleted_at IS NULL AND un.school_id = ?',
      );
      switch (filter) {
        case NotificationFilter.unread:
          where.write(' AND un.is_read = 0 AND un.is_archived = 0');
        case NotificationFilter.archived:
          where.write(' AND un.is_archived = 1');
        case NotificationFilter.all:
          where.write(' AND un.is_archived = 0');
      }
      if (cursor != null && cursor.isNotEmpty) {
        // Strictly older than the cursor, as the service does — items that
        // share the cursor's exact timestamp are skipped (see PARITY).
        where.write(' AND n.created_at < ?');
        params.add(cursor);
      }
      final int safe = limit.clamp(1, 200);

      final List<Row> rows = await _db.query('''
        SELECT n.id, n.action, n.entity_type, n.entity_id, n.title, n.message,
               n.metadata, n.priority, CAST(n.created_at AS CHAR) AS created_at,
               un.is_read, un.is_archived
          FROM notifications n
          JOIN user_notifications un ON n.id = un.notification_id
         WHERE $where
         ORDER BY n.created_at DESC
         LIMIT ${safe + 1}
        ''', params);

      final bool hasMore = rows.length > safe;
      final List<Row> page = hasMore ? rows.sublist(0, safe) : rows;
      final List<NotificationItem> items = page.map(_item).toList(growable: false);

      return Ok<NotificationPage>(
        NotificationPage(
          items: items,
          hasMore: hasMore,
          nextCursor: hasMore && items.isNotEmpty ? items.last.createdAtRaw : null,
        ),
      );
    } on Failure catch (failure) {
      return Err<NotificationPage>(failure);
    }
  }

  NotificationItem _item(Row r) {
    final String raw = SqlValue.asString(r['created_at']) ?? '';
    return NotificationItem(
      id: SqlValue.asInt(r['id']) ?? 0,
      title: SqlValue.asString(r['title']) ?? '',
      message: SqlValue.asString(r['message']),
      action: SqlValue.asString(r['action']),
      entityType: SqlValue.asString(r['entity_type']),
      entityId: SqlValue.asInt(r['entity_id']),
      metadata: parseMetadata(r['metadata']),
      priority: SqlValue.asString(r['priority']) ?? 'normal',
      createdAtRaw: raw,
      createdAt: SqlValue.asUtcInstant(raw),
      isRead: SqlValue.asBool(r['is_read']),
      isArchived: SqlValue.asBool(r['is_archived']),
    );
  }

  /// `metadata` is JSON text or already-decoded; anything unreadable is an
  /// empty map rather than a failed list — the service would throw here,
  /// which on a phone would blank the whole inbox over one bad row.
  static Map<String, Object?> parseMetadata(Object? raw) {
    try {
      final Object? v = raw is String && raw.isNotEmpty ? jsonDecode(raw) : raw;
      if (v is Map) {
        return v.map((Object? k, Object? x) => MapEntry<String, Object?>('$k', x));
      }
    } on FormatException {
      // Fall through.
    }
    return const <String, Object?>{};
  }

  @override
  Future<Result<int>> unreadCount() async {
    try {
      final Row? row = await _db.queryOne(
        'SELECT COUNT(*) AS count FROM user_notifications un '
        'WHERE un.user_id = ? AND un.is_read = 0 AND un.is_archived = 0 AND un.school_id = ?',
        <Object?>[_userId, _schoolId],
      );
      return Ok<int>(SqlValue.asInt(row?['count']) ?? 0);
    } on Failure {
      // getUnreadCount() returns 0 on error rather than failing.
      return const Ok<int>(0);
    }
  }

  @override
  Future<Result<void>> markRead(List<int> ids) => _update(
    ids,
    'UPDATE user_notifications SET is_read = 1, read_at = CURRENT_TIMESTAMP '
    'WHERE notification_id IN (%) AND user_id = ? AND is_read = 0',
  );

  @override
  Future<Result<void>> archive(List<int> ids) => _update(
    ids,
    'UPDATE user_notifications SET is_archived = 1, archived_at = CURRENT_TIMESTAMP '
    'WHERE notification_id IN (%) AND user_id = ? AND is_archived = 0',
  );

  Future<Result<void>> _update(List<int> ids, String sql) async {
    if (ids.isEmpty) {
      return const Err<void>(ValidationFailure(message: 'Invalid notification IDs'));
    }
    try {
      await _db.execute(
        sql.replaceFirst('%', List<String>.filled(ids.length, '?').join(',')),
        <Object?>[...ids, _userId],
      );
      return const Ok<void>(null);
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }
}
