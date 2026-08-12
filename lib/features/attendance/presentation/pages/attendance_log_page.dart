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
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/drais_bottom_nav.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// Who came, and when.
///
/// The attendance log is the screen DRAIS exists for: an append-only record of
/// every punch, from every device. It answers four things at once, because on
/// this data they are inseparable —
///
/// * **who** arrived, and **when**;
/// * **where from** — which device, or whether a person entered it;
/// * whether DRAIS is confident it was **really them**;
/// * whether the device **clock** can be believed.
///
/// A screen that showed only names and times would look tidier and hide the
/// two failures that actually matter in the field: an unidentified punch, and
/// a device whose clock has drifted far enough to turn "on time" into "late".
class AttendanceLogPage extends ConsumerStatefulWidget {
  /// Creates the attendance log page.
  const AttendanceLogPage({super.key});

  @override
  ConsumerState<AttendanceLogPage> createState() => _AttendanceLogPageState();
}

class _AttendanceLogPageState extends ConsumerState<AttendanceLogPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load ahead of the edge so the list does not visibly stall.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(attendanceLogControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AttendanceLogState state = ref.watch(attendanceLogControllerProvider);
    final AttendanceLogController controller = ref.read(
      attendanceLogControllerProvider.notifier,
    );
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Attendance log',
        subtitle:
            '${describeLocalDate(state.query.date)} · '
            '${state.summary.punches} punches',
        busy: state.isLoading && state.entries.isNotEmpty,
        // Carries the day's headline concern into the chrome, so it is visible
        // even when the summary has scrolled away.
        accentStrip: state.hasClockConcerns
            ? DraisColors.forAttendanceStatus('late', isDark: false)
            : null,
        actions: <Widget>[
          IconButton(
            icon: Icon(
              state.query.onlyNeedingAttention
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
            ),
            tooltip: 'Needs attention only',
            onPressed: controller.toggleAttentionOnly,
          ),
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: 'Today',
            onPressed: controller.goToToday,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: (String value) => context.push(value),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: AppRoutes.attendanceTrends,
                child: ListTile(
                  leading: Icon(Icons.show_chart),
                  title: Text('Trends'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: AppRoutes.unmatchedPunches,
                child: ListTile(
                  leading: Icon(Icons.person_search_outlined),
                  title: Text('Unidentified punches'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: _DateAndAudienceBar(state: state, controller: controller),
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: _body(state, controller, theme),
      ),
    );
  }

  Widget _body(
    AttendanceLogState state,
    AttendanceLogController controller,
    ThemeData theme,
  ) {
    if (state.isLoading && state.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final Failure? failure = state.failure;
    if (failure != null && state.entries.isEmpty) {
      return ErrorView.fromFailure(
        failure,
        onRetry: controller.load,
        environment: ref.read(appConfigProvider).environment,
      );
    }

    return ListView.separated(
      controller: _scroll,
      // Always scrollable, so pull-to-refresh works on an empty day.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        DraisBottomNav.reservedHeight,
      ),
      itemCount: state.entries.length + 2,
      separatorBuilder: (BuildContext context, int i) =>
          SizedBox(height: i == 0 ? 12 : 8),
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) return _DaySummaryCard(state: state);

        if (i == state.entries.length + 1) {
          if (state.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.isEmpty) return const _EmptyDay();
          return const SizedBox.shrink();
        }

        return _LogRow(entry: state.entries[i - 1]);
      },
    );
  }
}

/// Date stepper and audience filter, docked under the app bar.
class _DateAndAudienceBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _DateAndAudienceBar({required this.state, required this.controller});

  final AttendanceLogState state;
  final AttendanceLogController controller;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final bool atToday = isToday(state.query.date);

    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous day',
              onPressed: () => controller.shiftDate(-1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  describeLocalDate(state.query.date),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next day',
              // Never step into the future: there is no attendance to show,
              // and offering it invites the reader to think there might be.
              onPressed: atToday ? null : () => controller.shiftDate(1),
            ),
            const SizedBox(width: 4),
            SegmentedButton<AttendanceAudience>(
              segments: const <ButtonSegment<AttendanceAudience>>[
                ButtonSegment<AttendanceAudience>(
                  value: AttendanceAudience.all,
                  label: Text('All'),
                ),
                ButtonSegment<AttendanceAudience>(
                  value: AttendanceAudience.students,
                  label: Text('Students'),
                ),
                ButtonSegment<AttendanceAudience>(
                  value: AttendanceAudience.staff,
                  label: Text('Staff'),
                ),
              ],
              selected: <AttendanceAudience>{state.query.audience},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (Set<AttendanceAudience> s) =>
                  controller.setAudience(s.first),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// The day's verdict counts, plus the two warnings that change how to read
/// them.
class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({required this.state});

  final AttendanceLogState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final AttendanceDaySummary s = state.summary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _Stat(
                  label: 'Present',
                  value: s.present,
                  color: DraisColors.forAttendanceStatus(
                    'present',
                    isDark: isDark,
                  ),
                ),
                _Stat(
                  label: 'Late',
                  value: s.late,
                  color: DraisColors.forAttendanceStatus(
                    'late',
                    isDark: isDark,
                  ),
                ),
                _Stat(
                  label: 'Absent',
                  value: s.absent,
                  color: DraisColors.forAttendanceStatus(
                    'absent',
                    isDark: isDark,
                  ),
                ),
                _Stat(
                  label: 'Punches',
                  value: s.punches,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),

            // Unidentified punches are recoverable — the event is kept, and an
            // operator can claim it later — but only if somebody sees it.
            if (s.unmatchedPunches > 0) ...<Widget>[
              const SizedBox(height: 12),
              _Notice(
                icon: Icons.person_search_outlined,
                color: DraisColors.forAttendanceStatus(
                  'half_day',
                  isDark: isDark,
                ),
                text:
                    '${s.unmatchedPunches} punch'
                    '${s.unmatchedPunches == 1 ? '' : 'es'} could not be '
                    'matched to a person.',
              ),
            ],

            // The one that changes the meaning of every other number here.
            if (state.hasClockConcerns) ...<Widget>[
              const SizedBox(height: 8),
              _Notice(
                icon: Icons.schedule_outlined,
                color: DraisColors.forAttendanceStatus('late', isDark: isDark),
                text:
                    'A device clock is out by more than a minute. '
                    'Arrival times on this day may not be accurate.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

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
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
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

/// One punch.
class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final AttendanceLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final Color accent = entry.matched
        ? DraisColors.forAttendanceStatus('present', isDark: isDark)
        : DraisColors.forAttendanceStatus('half_day', isDark: isDark);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Time first: on a log, "when" is the column the eye scans.
            SizedBox(
              width: 52,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    formatClockTime(entry.punchAt),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  if (entry.ioMode != null)
                    Text(
                      entry.ioMode == 0 ? 'in' : 'out',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),

            Container(
              width: 3,
              height: 38,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.personLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      DraisPill(
                        label: entry.source.label,
                        color: theme.colorScheme.onSurfaceVariant,
                        icon: entry.source.isFromDevice
                            ? Icons.sensors
                            : Icons.edit_outlined,
                      ),
                      if (!entry.matched)
                        DraisPill(
                          label: 'Unidentified',
                          color: DraisColors.forAttendanceStatus(
                            'half_day',
                            isDark: isDark,
                          ),
                          icon: Icons.person_search_outlined,
                        ),
                      if (entry.hasMeaningfulSkew)
                        DraisPill(
                          label: 'Clock ${entry.skewLabel}',
                          color: DraisColors.forAttendanceStatus(
                            'late',
                            isDark: isDark,
                          ),
                          icon: Icons.schedule,
                        ),
                      if (entry.isProvisional)
                        DraisPill(
                          label: 'Provisional',
                          color: DraisColors.forAttendanceStatus(
                            'half_day',
                            isDark: isDark,
                          ),
                          icon: Icons.hourglass_empty,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.inbox_outlined,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('No punches recorded', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            // Says what it means rather than just what is missing: on a school
            // day, silence usually means a device stopped reporting.
            'Nothing was recorded for this day. On a school day this usually '
            'means the attendance devices did not report.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
