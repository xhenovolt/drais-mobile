import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/features/attendance/domain/entities/attendance_history.dart';
import 'package:drais/features/attendance/domain/entities/attendance_insights.dart';
import 'package:drais/features/attendance/presentation/widgets/history_row_tile.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';

/// One person's attendance: who they are, what DRAIS makes of their pattern,
/// their day-by-day verdicts, and their latest punches.
///
/// Built from the same two routes the web app uses for this drill-down —
/// `/api/attendance/person-profiles?person_id=` for the profile and series,
/// `/api/attendance/history?person_id=` for the punches.
class PersonAttendancePage extends ConsumerStatefulWidget {
  /// Creates the page.
  const PersonAttendancePage({
    required this.personId,
    required this.role,
    this.initialName,
    super.key,
  });

  /// `people.id`.
  final int personId;

  /// `student` or `staff`.
  final String role;

  /// Shown while the punches load.
  final String? initialName;

  @override
  ConsumerState<PersonAttendancePage> createState() =>
      _PersonAttendancePageState();
}

class _PersonAttendancePageState extends ConsumerState<PersonAttendancePage> {
  /// The route's default window.
  int _days = 30;

  ({int personId, String role, int days}) get _key =>
      (personId: widget.personId, role: widget.role, days: _days);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PersonAttendance> profile = ref.watch(
      personAttendanceProvider(_key),
    );
    final AsyncValue<AttendanceHistoryPage> punches = ref.watch(
      personPunchesProvider(widget.personId),
    );

    final AttendanceHistoryRow? sample = punches.valueOrNull?.rows.firstOrNull;
    final String name = sample?.label ?? widget.initialName ?? 'Person';

    return Scaffold(
      appBar: DraisAppBar(
        title: name,
        subtitle: widget.role == 'staff' ? 'Staff' : 'Learner',
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(personAttendanceProvider(_key))
            ..invalidate(personPunchesProvider(widget.personId));
          await ref.read(personAttendanceProvider(_key).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            _IdentityCard(name: name, sample: sample, role: widget.role),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 14, label: Text('14 d')),
                ButtonSegment<int>(value: 30, label: Text('30 d')),
                ButtonSegment<int>(value: 60, label: Text('60 d')),
                ButtonSegment<int>(value: 120, label: Text('120 d')),
              ],
              selected: <int>{_days},
              showSelectedIcon: false,
              onSelectionChanged: (Set<int> s) =>
                  setState(() => _days = s.first),
            ),
            const SizedBox(height: 12),
            profile.when(
              data: (PersonAttendance p) => Column(
                children: <Widget>[
                  _ProfileCard(profile: p.profile),
                  const SizedBox(height: 12),
                  _SeriesCard(series: p.series),
                ],
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object e, StackTrace _) => _InlineError(error: e),
            ),
            const SizedBox(height: 20),
            Text('Latest punches', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            punches.when(
              data: (AttendanceHistoryPage page) => page.rows.isEmpty
                  ? const Text('No punches recorded.')
                  : Column(
                      children: <Widget>[
                        for (final AttendanceHistoryRow r in page.rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: HistoryRowTile(
                              row: r,
                              offsetMinutes: page.offsetMinutes,
                              showDate: true,
                            ),
                          ),
                      ],
                    ),
              loading: () => const LinearProgressIndicator(),
              error: (Object e, StackTrace _) => _InlineError(error: e),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.name,
    required this.sample,
    required this.role,
  });

  final String name;
  final AttendanceHistoryRow? sample;
  final String role;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AttendanceHistoryRow? s = sample;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            PersonAvatar(
              initials: s?.initials ?? '?',
              photoUrl: s?.photoUrl,
              radius: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: theme.textTheme.titleMedium),
                  if (s?.subtitle != null)
                    Text(
                      s!.subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (s?.gender != null)
                    Text(
                      s!.gender!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color tone = profile.watch
        ? DraisColors.forAttendanceStatus('absent', isDark: isDark)
        : profile.rosterReview
        ? DraisColors.forAttendanceStatus('half_day', isDark: isDark)
        : DraisColors.forAttendanceStatus('present', isDark: isDark);

    String pct(double r) => '${(r * 100).round()}%';

    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                DraisPill(label: profile.label, color: tone, filled: true),
                const Spacer(),
                Text(
                  '${profile.trackedDays} tracked days',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(profile.note, style: theme.textTheme.bodyMedium),
            if (profile.behaviour != Behaviour.insufficientData) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  stat('Present', pct(profile.presentRate)),
                  stat('Late', pct(profile.lateRate)),
                  stat('Absent', pct(profile.absentRate)),
                  stat(
                    'Absent streak',
                    '${profile.currentAbsentStreak}'
                        ' / ${profile.longestAbsentStreak}',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Every day's verdict as a coloured square, oldest first — the shape of
/// the pattern at a glance.
class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.series});

  final List<PersonDay> series;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Day by day', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            if (series.isEmpty)
              Text(
                'No verdicts in this window.',
                style: theme.textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: <Widget>[
                  for (final PersonDay d in series)
                    Tooltip(
                      message: '${describeLocalDate(d.date)} · '
                          '${d.status.replaceAll('_', ' ')}',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: DraisColors.forAttendanceStatus(
                            d.status,
                            isDark: isDark,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: <Widget>[
                for (final String s in <String>[
                  'present',
                  'late',
                  'absent',
                  'half_day',
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        color: DraisColors.forAttendanceStatus(
                          s,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        s.replaceAll('_', ' '),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message = error is Failure
        ? (error as Failure).message
        : 'Something went wrong loading this.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
