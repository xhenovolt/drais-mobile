import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/features/attendance/domain/entities/attendance_history.dart';
import 'package:drais/features/attendance/domain/entities/attendance_insights.dart';
import 'package:drais/features/attendance/presentation/pages/attendance_log_page.dart';
import 'package:drais/features/auth/application/auth_state.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';
import 'package:drais/features/setup/data/setup_direct_repository.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/drais_bottom_nav.dart';
import 'package:drais/shared/widgets/loading_view.dart';

/// The home screen: today's attendance, without a tap.
///
/// ## What replaced what
///
/// This used to be a diagnostic dump — identity, roles, permission codes,
/// subscription — built to prove the auth foundation worked. It did its job
/// and then stayed, so the app opened on debugging output with the actual
/// product one tap behind it.
///
/// DRAIS is an attendance system, so the home screen opens on attendance. The
/// identity detail moved to Profile, where someone looks for it deliberately;
/// the technical detail is in Diagnostics, where it already lived.
class HomePage extends ConsumerWidget {
  /// Creates the home page.
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final AsyncValue<TodayAttendance> today = ref.watch(
      todayAttendanceProvider,
    );
    final AsyncValue<bool> connectivity = ref.watch(connectivityProvider);
    final AuthUser? user = auth.user;

    if (user == null) {
      return const Scaffold(body: LoadingView(label: 'Loading…'));
    }

    final bool offline =
        connectivity.valueOrNull == false ||
        auth.status == AuthStatus.offlineUnverified;

    return Scaffold(
      appBar: DraisAppBar(
        title: user.school?.name ?? 'DRAIS',
        subtitle: describeLocalDate(toLocalDateStr()),
        busy: today.isLoading && today.hasValue,
        leading: Builder(
          builder: (BuildContext context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: Scaffold.of(context).openDrawer,
          ),
        ),
        actions: <Widget>[
          const _NotificationBell(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(todayAttendanceProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(authControllerProvider.notifier).refresh();
          ref.invalidate(todayAttendanceProvider);
          await ref.read(todayAttendanceProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            DraisBottomNav.reservedHeight,
          ),
          children: <Widget>[
            if (offline)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: NoticeBanner(
                  message:
                      'You are offline. Showing the last information '
                      'DRAIS sent to this device.',
                  icon: Icons.wifi_off_outlined,
                  tone: NoticeTone.error,
                ),
              ),

            if (auth.warning != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NoticeBanner(
                  message: auth.warning!,
                  icon: Icons.warning_amber_outlined,
                  tone: NoticeTone.warning,
                ),
              ),

            // Keeps nagging after a skip, and names exactly what is missing
            // rather than saying "setup incomplete" and leaving them to guess.
            const _SetupNudge(),

            _TodayCard(today: today),
            const SizedBox(height: 12),
            _RecentArrivals(today: today),
            const SizedBox(height: 12),
            _QuickActions(user: user),

            const SizedBox(height: 20),
            Text(
              'Attendance is live from your devices. Finance, students and '
              'timetable arrive in later releases.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The inbox, with its unread count — `GET /api/notifications/unread-count`.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : '$unread unread notifications',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await context.push(AppRoutes.notifications);
        ref.invalidate(unreadNotificationsProvider);
      },
    );
  }
}

/// Reminds a school that has skipped setup, naming what is still missing.
///
/// Reads what actually exists rather than the `setup_complete` flag, so a
/// school configured on the web stops being nagged even though nothing here
/// ever flipped it.
class _SetupNudge extends ConsumerWidget {
  const _SetupNudge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<SetupStatus> status = ref.watch(setupStatusProvider);

    return status.maybeWhen(
      data: (SetupStatus s) {
        if (s.isUsable) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            color: theme.colorScheme.tertiaryContainer,
            child: InkWell(
              onTap: () => context.push(AppRoutes.schoolSetup),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.tune,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Finish setting up your school',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Attendance needs ${s.missing.join(' and ')}.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      // A failed status check must not push an alarming card at someone; the
      // rest of the screen still works.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Today's headline numbers — the dashboard's attendance block
/// (`getDashboardAttendanceCounts()`), labelled by role as the web dashboard
/// insists: never an unlabelled 0/0/0.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today});

  final AsyncValue<TodayAttendance> today;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final TodayAttendance? data = today.valueOrNull;
    if (data == null && today.isLoading) {
      return const Card(
        child: SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (data == null) {
      final Object? error = today.error;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  error is Failure
                      ? error.message
                      : 'Today\'s attendance could not be loaded.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final HistoryTabCounts? tabs = data.recent?.tabCounts;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AttendanceCountsRow(
              title: 'Learners',
              counts: data.counts.students,
              large: true,
            ),
            const Divider(height: 24),
            AttendanceCountsRow(title: 'Staff', counts: data.counts.staff),
            if (tabs != null) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.sensors,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${tabs.all} punch${tabs.all == 1 ? '' : 'es'} recorded',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (tabs.unmatched > 0) ...<Widget>[
                const SizedBox(height: 8),
                _Warning(
                  icon: Icons.person_search_outlined,
                  color: DraisColors.forAttendanceStatus(
                    'half_day',
                    isDark: isDark,
                  ),
                  text:
                      '${tabs.unmatched} punch'
                      '${tabs.unmatched == 1 ? '' : 'es'} not matched to a '
                      'person.',
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The latest punches, as a taste of the full log.
class _RecentArrivals extends StatelessWidget {
  const _RecentArrivals({required this.today});

  final AsyncValue<TodayAttendance> today;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AttendanceHistoryPage? page = today.valueOrNull?.recent;
    final List<AttendanceHistoryRow> recent =
        page?.rows ?? const <AttendanceHistoryRow>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('Latest punches', style: theme.textTheme.titleSmall),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go(AppRoutes.attendanceLog),
                  child: const Text('See all'),
                ),
              ],
            ),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 12),
                child: Text(
                  today.isLoading ? 'Loading…' : 'Nothing recorded yet today.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...recent.map(
                (AttendanceHistoryRow r) => Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 10),
                  child: Row(
                    children: <Widget>[
                      Text(
                        formatClockTime(
                          schoolWallTime(
                            r.checkTime,
                            offsetMinutes: page!.offsetMinutes,
                          ),
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          r.label,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (r.derivedLabel != null)
                        Text(
                          r.derivedLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: DraisColors.forAttendanceStatus(
                              r.derivedStatusKey,
                              isDark:
                                  theme.brightness == Brightness.dark,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shortcuts, gated on what the user may actually do.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _ActionTile(
            icon: Icons.fact_check_outlined,
            label: 'Attendance log',
            onTap: () => context.go(AppRoutes.attendanceLog),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionTile(
            icon: Icons.sensors_outlined,
            label: 'Devices',
            onTap: () => context.go(AppRoutes.devices),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Column(
            children: <Widget>[
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
