import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// Attendance over time, and what it says about the data.
///
/// ## Not just a chart
///
/// A bar chart of daily attendance is easy to draw and easy to misread. The
/// thing worth surfacing is not "attendance was 92% on Tuesday" — it is
/// **whether the numbers are believable at all**.
///
/// Real attendance is a mix: some learners on time, some late, a few absent. A
/// day where *every single arrival* was classed the same way is almost never
/// behaviour. It is a device clock that has drifted, or a shift start time
/// that does not match when the school actually opens. This screen names those
/// days, because the fix is in settings rather than in a conversation with
/// learners — and nothing else in the app would tell you which.
class AttendanceTrendsPage extends ConsumerWidget {
  /// Creates the trends page.
  const AttendanceTrendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AttendanceTrendDay>> trend = ref.watch(
      attendanceTrendProvider,
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Attendance trends',
        subtitle: trend.maybeWhen(
          data: (List<AttendanceTrendDay> days) =>
              'Last ${days.length} recorded day'
              '${days.length == 1 ? '' : 's'}',
          orElse: () => 'Loading…',
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(attendanceTrendProvider),
          ),
        ],
      ),
      body: trend.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => ErrorView(
          title: 'Could not load trends',
          message: error is Failure ? error.message : 'Something went wrong.',
          onRetry: () => ref.invalidate(attendanceTrendProvider),
        ),
        data: (List<AttendanceTrendDay> days) {
          if (days.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No attendance recorded in this period.'),
              ),
            );
          }

          final List<AttendanceTrendDay> uniform = days
              .where((AttendanceTrendDay d) => d.isUniform)
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              if (uniform.isNotEmpty) ...<Widget>[
                _DataQualityWarning(days: uniform, total: days.length),
                const SizedBox(height: 12),
              ],
              _Chart(days: days),
              const SizedBox(height: 12),
              _Breakdown(days: days),
            ],
          );
        },
      ),
    );
  }
}

/// The finding that changes how every other number here should be read.
class _DataQualityWarning extends StatelessWidget {
  const _DataQualityWarning({required this.days, required this.total});

  final List<AttendanceTrendDay> days;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color colour = DraisColors.forAttendanceStatus(
      'late',
      isDark: isDark,
    );

    return Card(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.rule_folder_outlined, color: colour),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${days.length} of $total days look misclassified',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'On these days every single arrival was classed the same way. '
              'Real attendance is mixed, so this usually means a device clock '
              'has drifted or the shift start time does not match when the '
              'school actually opens — not that everyone behaved identically.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: days
                  .take(6)
                  .map(
                    (AttendanceTrendDay d) => DraisPill(
                      label:
                          '${describeLocalDate(toLocalDateStr(d.date))} · '
                          '${d.uniformLabel}',
                      color: colour,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// A stacked bar per day, oldest on the left.
class _Chart extends StatelessWidget {
  const _Chart({required this.days});

  final List<AttendanceTrendDay> days;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    // Reversed so time reads left to right, which is the only direction a
    // chart of dates can go without confusing everyone.
    final List<AttendanceTrendDay> ordered = days.reversed.toList();
    final int peak = ordered.fold<int>(
      1,
      (int max, AttendanceTrendDay d) => d.total > max ? d.total : max,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Daily attendance', style: theme.textTheme.titleSmall),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: ordered
                    .map(
                      (AttendanceTrendDay d) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _Bar(day: d, peak: peak, isDark: isDark),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: <Widget>[
                _Key(
                  label: 'Present',
                  color: DraisColors.forAttendanceStatus(
                    'present',
                    isDark: isDark,
                  ),
                ),
                _Key(
                  label: 'Late',
                  color: DraisColors.forAttendanceStatus(
                    'late',
                    isDark: isDark,
                  ),
                ),
                _Key(
                  label: 'Absent',
                  color: DraisColors.forAttendanceStatus(
                    'absent',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.day, required this.peak, required this.isDark});

  final AttendanceTrendDay day;
  final int peak;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    double height(int count) => count == 0 ? 0 : (count / peak) * 130;

    return Tooltip(
      message:
          '${toLocalDateStr(day.date)}\n'
          'Present ${day.present} · Late ${day.late} · Absent ${day.absent}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (day.isUniform)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Icon(
                Icons.priority_high,
                size: 11,
                color: DraisColors.forAttendanceStatus('late', isDark: isDark),
              ),
            ),
          _Segment(
            height: height(day.absent),
            color: DraisColors.forAttendanceStatus('absent', isDark: isDark),
            top: true,
          ),
          _Segment(
            height: height(day.late),
            color: DraisColors.forAttendanceStatus('late', isDark: isDark),
          ),
          _Segment(
            height: height(day.present),
            color: DraisColors.forAttendanceStatus('present', isDark: isDark),
            bottom: true,
          ),
          const SizedBox(height: 6),
          Text(
            '${day.date.day}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.height,
    required this.color,
    this.top = false,
    this.bottom = false,
  });

  final double height;
  final Color color;
  final bool top;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(top ? 3 : 0),
          bottom: Radius.circular(bottom ? 3 : 0),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The same data as rows, for anyone who wants the numbers.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.days});

  final List<AttendanceTrendDay> days;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('By day', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ...days.map(
              (AttendanceTrendDay d) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 96,
                      child: Text(
                        describeLocalDate(toLocalDateStr(d.date)),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (d.isUniform)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.priority_high,
                          size: 13,
                          color: DraisColors.forAttendanceStatus(
                            'late',
                            isDark: isDark,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      d.rate == null ? '—' : '${(d.rate! * 100).round()}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 66,
                      child: Text(
                        '${d.total} rec.',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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

/// Daily counts over the last two weeks.
final AutoDisposeFutureProvider<List<AttendanceTrendDay>>
attendanceTrendProvider = FutureProvider.autoDispose<List<AttendanceTrendDay>>((
  Ref ref,
) async {
  final Result<List<AttendanceTrendDay>> result = await ref
      .watch(attendanceRepositoryProvider)
      .trend();
  return result.fold(
    onOk: (List<AttendanceTrendDay> days) => days,
    onErr: (Failure failure) => throw failure,
  );
});
