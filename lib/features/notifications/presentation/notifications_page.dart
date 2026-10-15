import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/notifications/domain/notifications.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// The in-app inbox — the web `/notifications`.
///
/// Same tabs (All / Unread / Archived), same 50-at-a-time load, same
/// per-item read and archive actions, and the same client-side search over
/// what is loaded. Push delivery is not part of this: it needs a
/// device-token endpoint the platform does not have yet.
class NotificationsPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  NotificationFilter _filter = NotificationFilter.all;
  String _search = '';
  List<NotificationItem> _items = const <NotificationItem>[];
  String? _cursor;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final Result<NotificationPage> r = await ref
        .read(notificationsRepositoryProvider)
        .list(filter: _filter, limit: 50);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (r) {
        case Ok<NotificationPage>(:final NotificationPage value):
          _items = value.items;
          _cursor = value.nextCursor;
          _hasMore = value.hasMore;
        case Err<NotificationPage>(:final Failure failure):
          _failure = failure;
      }
    });
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final Result<NotificationPage> r = await ref
        .read(notificationsRepositoryProvider)
        .list(filter: _filter, cursor: _cursor, limit: 50);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (r case Ok<NotificationPage>(:final NotificationPage value)) {
        _items = <NotificationItem>[..._items, ...value.items];
        _cursor = value.nextCursor;
        _hasMore = value.hasMore;
      }
    });
  }

  Future<void> _act(
    Future<Result<void>> Function() run,
    String done,
  ) async {
    final Result<void> r = await run();
    if (!mounted) return;
    ref.invalidate(unreadNotificationsProvider);
    if (r case Err<void>(:final Failure failure)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    await _load();
  }

  /// Where a notification leads, when the app has that screen.
  String? _target(NotificationItem n) {
    final String? link = n.link;
    if (link != null) {
      final RegExpMatch? student = RegExp(
        r'^/students/(\d+)(?:[/?#].*)?$',
      ).firstMatch(link);
      if (student != null) {
        return AppRoutes.studentDetailPath(int.parse(student.group(1)!));
      }
      if (link.startsWith('/attendance')) return AppRoutes.attendanceLog;
      if (link.startsWith('/students')) return AppRoutes.students;
    }
    if (n.entityType == 'student' && n.entityId != null) {
      return AppRoutes.studentDetailPath(n.entityId!);
    }
    return null;
  }

  Future<void> _open(NotificationItem n) async {
    if (!n.isRead) {
      await ref.read(notificationsRepositoryProvider).markRead(<int>[n.id]);
      ref.invalidate(unreadNotificationsProvider);
    }
    if (!mounted) return;
    final String? to = _target(n);
    if (to != null) {
      await context.push(to);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String q = _search.trim().toLowerCase();
    final List<NotificationItem> shown = q.isEmpty
        ? _items
        : _items
              .where(
                (NotificationItem n) =>
                    n.title.toLowerCase().contains(q) ||
                    (n.message ?? '').toLowerCase().contains(q),
              )
              .toList();
    final List<int> unreadIds = <int>[
      for (final NotificationItem n in _items)
        if (!n.isRead) n.id,
    ];

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Notifications',
        subtitle: '${shown.length} notifications',
        actions: <Widget>[
          if (_filter != NotificationFilter.archived && unreadIds.isNotEmpty)
            TextButton(
              onPressed: () => _act(
                () => ref.read(notificationsRepositoryProvider).markRead(unreadIds),
                'Notifications marked as read',
              ),
              child: const Text('Mark all read'),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search loaded notifications',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (String v) => setState(() => _search = v),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: <Widget>[
                    for (final NotificationFilter f in NotificationFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 6),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) {
                            setState(() => _filter = f);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failure != null
          ? ErrorView.fromFailure(_failure!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: shown.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(40),
                      children: <Widget>[
                        Icon(
                          Icons.notifications_none,
                          size: 44,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _filter == NotificationFilter.unread
                              ? "You're all caught up."
                              : 'No notifications match your current filter.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: shown.length + (_hasMore ? 1 : 0),
                      itemBuilder: (BuildContext context, int i) {
                        if (i == shown.length) {
                          return TextButton(
                            onPressed: _loadingMore ? null : _more,
                            child: Text(_loadingMore ? 'Loading…' : 'Load older'),
                          );
                        }
                        return _NotificationTile(
                          n: shown[i],
                          onTap: () => _open(shown[i]),
                          onArchive: shown[i].isArchived
                              ? null
                              : () => _act(
                                  () => ref
                                      .read(notificationsRepositoryProvider)
                                      .archive(<int>[shown[i].id]),
                                  'Notifications archived',
                                ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.n,
    required this.onTap,
    required this.onArchive,
  });

  final NotificationItem n;
  final VoidCallback onTap;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ({IconData icon, Color color}) p = switch (n.priority) {
      'critical' => (icon: Icons.error, color: theme.colorScheme.error),
      'high' => (icon: Icons.priority_high, color: theme.colorScheme.tertiary),
      'low' => (
        icon: Icons.info_outline,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      _ => (icon: Icons.notifications_outlined, color: theme.colorScheme.primary),
    };
    final DateTime? at = n.createdAt;

    return Card(
      color: n.isRead ? null : theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: ListTile(
        onTap: onTap,
        leading: Icon(p.icon, color: p.color),
        title: Text(
          n.title,
          style: TextStyle(fontWeight: n.isRead ? null : FontWeight.w600),
        ),
        subtitle: Text(
          <String?>[
            n.message,
            if (at != null)
              '${describeLocalDate(toLocalDateStr(schoolWallTime(at)))} '
                  '${formatClockTime(schoolWallTime(at))}',
            n.entityType,
          ].whereType<String>().where((String s) => s.isNotEmpty).join(' · '),
        ),
        trailing: onArchive == null
            ? null
            : IconButton(
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'Archive',
                onPressed: onArchive,
              ),
      ),
    );
  }
}
