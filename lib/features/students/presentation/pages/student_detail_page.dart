import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/domain/student_summary.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// One learner: who they are, and whether they have been coming in.
///
/// The attendance history is the point. A roster row tells you a learner
/// exists; this tells you whether the school is actually seeing them, which is
/// the question a class teacher or a head of department is really asking when
/// they look someone up.
class StudentDetailPage extends ConsumerWidget {
  /// Creates the detail page.
  const StudentDetailPage({required this.studentId, super.key});

  /// `students.id`.
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StudentDetail> detail = ref.watch(
      studentDetailProvider(studentId),
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: detail.maybeWhen(
          data: (StudentDetail d) => d.summary.displayName,
          orElse: () => 'Learner',
        ),
        subtitle: detail.maybeWhen(
          data: (StudentDetail d) => <String>[
            if (d.summary.className != null) d.summary.className!,
            d.summary.admissionNo ?? 'No admission number',
          ].join(' · '),
          orElse: () => null,
        ),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => ErrorView(
          title: 'Could not load this learner',
          message: error is Failure ? error.message : 'Something went wrong.',
          onRetry: () => ref.invalidate(studentDetailProvider(studentId)),
        ),
        data: (StudentDetail d) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: <Widget>[
            _IdentityCard(detail: d),
            const SizedBox(height: 12),
            _AttendanceSummary(detail: d),
            const SizedBox(height: 12),
            _AttendanceHistory(detail: d),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.detail});

  final StudentDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StudentSummary s = detail.summary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 32,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundImage: detail.photoUrl == null
                      ? null
                      : NetworkImage(detail.photoUrl!),
                  child: Text(
                    s.initials,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          if (s.className != null)
                            DraisPill(
                              label: s.className!,
                              color: theme.colorScheme.primary,
                              icon: Icons.class_outlined,
                            ),
                          if (!s.isActive)
                            DraisPill(
                              label: s.status,
                              color: theme.colorScheme.error,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _Field(label: 'Admission no.', value: s.admissionNo),
            _Field(label: 'Gender', value: detail.gender),
            _Field(
              label: 'Age',
              value: detail.age == null ? null : '${detail.age} years',
            ),
            _Field(label: 'Phone', value: detail.phone),
            _Field(label: 'Email', value: detail.email),
            _Field(label: 'Address', value: detail.address),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? shown = value?.trim().isEmpty ?? true ? null : value!.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              // "Not recorded" rather than a blank: an empty field looks like
              // a rendering bug, and a missing value is often actionable.
              shown ?? 'Not recorded',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: shown == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
                fontStyle: shown == null ? FontStyle.italic : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceSummary extends StatelessWidget {
  const _AttendanceSummary({required this.detail});

  final StudentDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final double? rate = detail.attendanceRate;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Last 30 days', style: theme.textTheme.titleSmall),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        rate == null ? '—' : '${(rate * 100).round()}%',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: rate == null
                              ? theme.colorScheme.onSurfaceVariant
                              : DraisColors.forAttendanceStatus(
                                  rate >= 0.9
                                      ? 'present'
                                      : rate >= 0.75
                                      ? 'late'
                                      : 'absent',
                                  isDark: isDark,
                                ),
                        ),
                      ),
                      Text(
                        'Attendance',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _Count(
                  label: 'Attended',
                  value: detail.daysAttended,
                  color: DraisColors.forAttendanceStatus(
                    'present',
                    isDark: isDark,
                  ),
                ),
                _Count(
                  label: 'Absent',
                  value: detail.daysAbsent,
                  color: DraisColors.forAttendanceStatus(
                    'absent',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            if (rate == null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'No attendance recorded in this period.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.color});

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

class _AttendanceHistory extends StatelessWidget {
  const _AttendanceHistory({required this.detail});

  final StudentDetail detail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (detail.attendance.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('History', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ...detail.attendance.map(
              (StudentAttendanceDay day) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 92,
                      child: Text(
                        describeLocalDate(toLocalDateStr(day.date)),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    SizedBox(
                      width: 54,
                      child: Text(
                        formatClockTime(day.firstInAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    AttendanceStatusPill(day.status),
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

/// One learner's full record.
final AutoDisposeFutureProviderFamily<StudentDetail, int>
studentDetailProvider = FutureProvider.autoDispose.family<StudentDetail, int>((
  Ref ref,
  int studentId,
) async {
  final Result<StudentDetail> result = await ref
      .watch(studentsRepositoryProvider)
      .detail(studentId);
  return result.fold(
    onOk: (StudentDetail detail) => detail,
    onErr: (Failure failure) => throw failure,
  );
});
