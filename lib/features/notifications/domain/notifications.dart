import 'package:drais/core/error/result.dart';

/// Which notifications a list shows — the web page's three tabs.
enum NotificationFilter {
  /// Everything not archived.
  all('all', 'All'),

  /// Unread and not archived.
  unread('unread', 'Unread'),

  /// Archived only.
  archived('archived', 'Archived');

  const NotificationFilter(this.wireValue, this.label);

  /// The route's `filter`.
  final String wireValue;

  /// Tab label.
  final String label;
}

/// One notification for the signed-in user — a row of
/// `notifications` joined to `user_notifications`.
class NotificationItem {
  /// Creates an item.
  const NotificationItem({
    required this.id,
    required this.title,
    required this.createdAtRaw,
    this.message,
    this.action,
    this.entityType,
    this.entityId,
    this.metadata = const <String, Object?>{},
    this.priority = 'normal',
    this.createdAt,
    this.isRead = false,
    this.isArchived = false,
  });

  /// `notifications.id`.
  final int id;

  /// Heading.
  final String title;

  /// Body.
  final String? message;

  /// e.g. `STUDENT_ENROLLED`.
  final String? action;

  /// e.g. `student`, `enrollment`.
  final String? entityType;

  /// The entity's id.
  final int? entityId;

  /// Parsed `metadata` JSON; may carry a `link`.
  final Map<String, Object?> metadata;

  /// `low` | `normal` | `high` | `critical`.
  final String priority;

  /// `created_at` exactly as stored — the paging cursor.
  final String createdAtRaw;

  /// `created_at` as a UTC instant.
  final DateTime? createdAt;

  /// `user_notifications.is_read`.
  final bool isRead;

  /// `user_notifications.is_archived`.
  final bool isArchived;

  /// `metadata.link`, the web path to open, when present.
  String? get link {
    final Object? l = metadata['link'];
    return l is String && l.isNotEmpty ? l : null;
  }
}

/// One page, with the service's cursor.
class NotificationPage {
  /// Creates a page.
  const NotificationPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  /// Newest first.
  final List<NotificationItem> items;

  /// Whether older items exist.
  final bool hasMore;

  /// Pass back as `cursor` for the next page.
  final String? nextCursor;
}

/// The signed-in user's notifications.
///
/// | Method | LongTerm source |
/// |---|---|
/// | [list] | `GET /api/notifications/list` → `NotificationService.list` |
/// | [unreadCount] | `GET /api/notifications/unread-count` |
/// | [markRead] | `POST /api/notifications/mark-read` |
/// | [archive] | `POST /api/notifications/archive` |
abstract interface class NotificationsRepository {
  /// A page of notifications.
  Future<Result<NotificationPage>> list({
    NotificationFilter filter = NotificationFilter.all,
    String? cursor,
    int limit = 25,
  });

  /// Unread, unarchived count.
  Future<Result<int>> unreadCount();

  /// Marks [ids] read.
  Future<Result<void>> markRead(List<int> ids);

  /// Archives [ids].
  Future<Result<void>> archive(List<int> ids);
}
