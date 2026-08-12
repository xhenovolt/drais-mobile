import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/features/attendance/application/attendance_log_controller.dart';
import 'package:drais/features/attendance/domain/entities/attendance_log_entry.dart';
import 'package:drais/features/attendance/domain/repositories/attendance_repository.dart';
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
    final AttendanceLogState log = ref.watch(attendanceLogControllerProvider);
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
        busy: log.isLoading && log.entries.isNotEmpty,
        leading: Builder(
          builder: (BuildContext context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: Scaffold.of(context).openDrawer,
          ),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(attendanceLogControllerProvider.notifier).load(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(authControllerProvider.notifier).refresh();
          await ref.read(attendanceLogControllerProvider.notifier).load();
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

            _TodayCard(state: log),
            const SizedBox(height: 12),
            _RecentArrivals(state: log),
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

/// Today's headline numbers.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.state});

  final AttendanceLogState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final AttendanceDaySummary s = state.summary;

    if (state.isLoading && state.entries.isEmpty) {
      return const Card(
        child: SizedBox(
          height: 132,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final Failure? failure = state.failure;
    if (failure != null && state.entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(failure.message, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _Metric(
                  label: 'Present',
                  value: s.present,
                  color: DraisColors.forAttendanceStatus(
                    'present',
                    isDark: isDark,
                  ),
                ),
                _Metric(
                  label: 'Late',
                  value: s.late,
                  color: DraisColors.forAttendanceStatus(
                    'late',
                    isDark: isDark,
                  ),
                ),
                _Metric(
                  label: 'Absent',
                  value: s.absent,
                  color: DraisColors.forAttendanceStatus(
                    'absent',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
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
                  '${s.punches} punch${s.punches == 1 ? '' : 'es'} recorded',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // The thing a head teacher must see before trusting the numbers
            // above it — a drifting clock changes what "late" means.
            if (state.hasClockConcerns) ...<Widget>[
              const SizedBox(height: 10),
              _Warning(
                icon: Icons.schedule_outlined,
                color: DraisColors.forAttendanceStatus('late', isDark: isDark),
                text:
                    'A device clock is out by more than a minute. '
                    'Arrival times today may not be accurate.',
              ),
            ],
            if (s.unmatchedPunches > 0) ...<Widget>[
              const SizedBox(height: 8),
              _Warning(
                icon: Icons.person_search_outlined,
                color: DraisColors.forAttendanceStatus(
                  'half_day',
                  isDark: isDark,
                ),
                text:
                    '${s.unmatchedPunches} punch'
                    '${s.unmatchedPunches == 1 ? '' : 'es'} not matched to a '
                    'person.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$value',
            style: theme.textTheme.displaySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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

/// The last few arrivals, as a taste of the full log.
class _RecentArrivals extends StatelessWidget {
  const _RecentArrivals({required this.state});

  final AttendanceLogState state;

  /// Enough to show the day is alive, few enough that the card stays a
  /// summary rather than becoming a second log screen.
  static const int _maxRows = 4;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final List<AttendanceLogEntry> recent = state.entries
        .take(_maxRows)
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text('Recent arrivals', style: theme.textTheme.titleSmall),
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
                  state.isLoading ? 'Loading…' : 'Nothing recorded yet today.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...recent.map(
                (AttendanceLogEntry e) => Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 10),
                  child: Row(
                    children: <Widget>[
                      Text(
                        formatClockTime(e.punchAt),
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
                          e.personLabel,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (e.needsAttention)
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: theme.colorScheme.tertiary,
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
