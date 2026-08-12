import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/timehealth/domain/health_report.dart';
import 'package:drais/features/timehealth/domain/time_health.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/drais_bottom_nav.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// Can today's attendance be trusted?
///
/// ## The question this screen answers
///
/// DRAIS records attendance from biometric devices. Two silent failures make
/// the register wrong without anything on an attendance screen saying so:
///
/// * **A device stops reporting.** Nobody is marked absent because nobody was
///   scanned — and an empty day looks the same as a holiday.
/// * **A device clock drifts.** Everyone is marked late, or nobody is, and the
///   times look perfectly plausible.
///
/// Both are invisible from the log itself, which is why this is its own screen
/// and its own tab rather than a panel somewhere.
///
/// ## Judged against each device's own normal
///
/// "239 punches today" means nothing on its own. The platform keeps a rolling
/// baseline per device — typical first arrival, typical daily volume — and
/// everything here is read against that. A gate reader and a staff-room reader
/// have completely different normals, so a shared threshold would be wrong for
/// both.
class TimeHealthPage extends ConsumerWidget {
  /// Creates the time health page.
  const TimeHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AttendanceDevice>> devices = ref.watch(
      attendanceDevicesProvider,
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Time health',
        subtitle: devices.maybeWhen(
          data: (List<AttendanceDevice> list) {
            final int unhealthy = list
                .where((AttendanceDevice d) => !d.isHealthy)
                .length;
            return unhealthy == 0
                ? '${list.length} device${list.length == 1 ? '' : 's'} · all well'
                : '$unhealthy of ${list.length} need attention';
          },
          orElse: () => describeLocalDate(toLocalDateStr()),
        ),
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
            onPressed: () => ref.invalidate(attendanceDevicesProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(attendanceDevicesProvider),
        child: devices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => ErrorView(
            title: 'Could not check device health',
            message: error is Failure ? error.message : 'Something went wrong.',
            onRetry: () => ref.invalidate(attendanceDevicesProvider),
          ),
          data: (List<AttendanceDevice> list) {
            if (list.isEmpty) return const _NoDevices();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                DraisBottomNav.reservedHeight,
              ),
              children: <Widget>[
                const _HealthScoreCard(),
                const SizedBox(height: 12),
                _Verdict(devices: list),
                const SizedBox(height: 12),
                ...list.map(
                  (AttendanceDevice d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DeviceCard(device: d),
                  ),
                ),
                const SizedBox(height: 8),
                const _PolicyCard(),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One sentence at the top saying whether to worry.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.devices});

  final List<AttendanceDevice> devices;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final List<AttendanceDevice> unhealthy = devices
        .where((AttendanceDevice d) => !d.isHealthy)
        .toList();
    final bool allWell = unhealthy.isEmpty;

    final Color colour = DraisColors.forAttendanceStatus(
      allWell ? 'present' : 'late',
      isDark: isDark,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              allWell ? Icons.verified_outlined : Icons.warning_amber_outlined,
              color: colour,
              size: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    allWell
                        ? 'Today\'s attendance can be trusted'
                        : 'Today\'s attendance may be affected',
                    style: theme.textTheme.titleSmall?.copyWith(color: colour),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    allWell
                        ? 'Every device is reporting, and the clocks agree '
                              'with DRAIS.'
                        : unhealthy
                              .expand((AttendanceDevice d) => d.concerns)
                              .toSet()
                              .join(' · '),
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

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final AttendanceDevice device;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final DeviceBaseline? baseline = device.baseline;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.sensors,
                  color: device.isHealthy
                      ? DraisColors.forAttendanceStatus(
                          'present',
                          isDark: isDark,
                        )
                      : DraisColors.forAttendanceStatus('late', isDark: isDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        device.name?.isNotEmpty ?? false
                            ? device.name!
                            : device.serialNumber,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        <String>[
                          if (device.location != null) device.location!,
                          device.serialNumber,
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                DraisPill(
                  label: device.isOnline ? 'Online' : 'Offline',
                  color: DraisColors.forAttendanceStatus(
                    device.isOnline ? 'present' : 'absent',
                    isDark: isDark,
                  ),
                  icon: device.isOnline ? Icons.wifi : Icons.wifi_off,
                ),
              ],
            ),

            if (device.concerns.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              ...device.concerns.map(
                (String concern) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.error_outline,
                        size: 14,
                        color: DraisColors.forAttendanceStatus(
                          'late',
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(concern, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),

            _Row(
              label: 'Punches today',
              value: baseline?.medianDailyPunches == null
                  ? '${device.punchesToday}'
                  : '${device.punchesToday}  (usually '
                        '${baseline!.medianDailyPunches})',
            ),
            if (baseline?.medianFirstArrival != null)
              _Row(
                label: 'Usual first arrival',
                value:
                    '${baseline!.medianFirstArrival}'
                    '${baseline.earlyEdge != null ? '  (${baseline.earlyEdge}–${baseline.lateEdge})' : ''}',
              ),
            _Row(
              label: 'Last activity',
              value: device.lastActivity == null
                  ? 'Never'
                  : '${formatClockTime(device.lastActivity)} · '
                        '${describeLocalDate(toLocalDateStr(device.lastActivity!))}',
            ),
            if (device.ipAddress != null)
              _Row(label: 'Address', value: device.ipAddress!),

            if (baseline != null && !baseline.isReliable) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                // Say so rather than quietly comparing against a shaky number.
                'Baseline is still forming — ${baseline.sampleDays ?? 0} days '
                'of history so far.',
                style: theme.textTheme.labelSmall?.copyWith(
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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _PolicyCard extends ConsumerWidget {
  const _PolicyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<TimePolicy> policy = ref.watch(timePolicyProvider);

    return policy.maybeWhen(
      data: (TimePolicy p) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Time policy', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10),
              _Row(label: 'Timezone', value: p.timezone),
              _Row(
                label: 'Offset',
                value:
                    'UTC${p.utcOffsetMinutes >= 0 ? '+' : ''}'
                    '${(p.utcOffsetMinutes / 60).toStringAsFixed(0)}',
              ),
              if (p.devicePolicy != null)
                _Row(label: 'Device policy', value: p.devicePolicy!),
              if (!p.isConfigured) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Using platform defaults — this school has not set its own '
                  'time policy.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _NoDevices extends StatelessWidget {
  const _NoDevices();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.sensors_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No devices registered', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Attendance devices are registered from the DRAIS web app. '
              'Until one is, attendance can only be recorded manually.',
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

/// Devices with today's health attached.
/// The school's Attendance Health Score, exactly as the web app computes it.
///
/// Ten weighted checks across the pipeline — devices, heartbeats, punch
/// volume, clock confidence, SMS, identity matching, queue, jobs, database,
/// clock reputation. See `domain/health_report.dart` for why every number in
/// it is transcribed rather than chosen.
final AutoDisposeFutureProvider<HealthReport> attendanceHealthProvider =
    FutureProvider.autoDispose<HealthReport>((Ref ref) async {
      final Result<HealthReport> result = await ref
          .watch(timeHealthRepositoryProvider)
          .runHealthChecks();
      return result.fold(
        onOk: (HealthReport report) => report,
        onErr: (Failure failure) => throw failure,
      );
    });

/// The headline score, with the worst problems listed under it.
class _HealthScoreCard extends ConsumerWidget {
  const _HealthScoreCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<HealthReport> health = ref.watch(attendanceHealthProvider);

    return health.when(
      // Ten queries take a moment. The card holds its shape while they run so
      // the list below does not jump once the score lands.
      loading: () => const Card(
        child: SizedBox(
          height: 132,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      // A failed rollup is not worth an error screen — the device list below
      // is still perfectly readable without it.
      error: (Object error, StackTrace _) => Card(
        child: ListTile(
          leading: Icon(Icons.help_outline, color: theme.colorScheme.outline),
          title: const Text('Health score unavailable'),
          subtitle: Text(
            error is Failure ? error.message : 'Could not run the checks.',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(attendanceHealthProvider),
          ),
        ),
      ),
      data: (HealthReport report) {
        final Color color = _healthColor(report.status, theme);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 62,
                      height: 62,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: report.score / 100,
                              strokeWidth: 6,
                              backgroundColor: color.withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                          Text(
                            '${report.score}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Attendance health: ${report.status.label}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${report.usableChecks.length} checks across '
                            'devices, clocks, identity and delivery.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (report.recommendations.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // Worst first — the platform sorts them that way, and the
                  // first line is the one someone will act on.
                  for (final String recommendation in report.recommendations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.arrow_right,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              recommendation,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (report.failedChecks.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '${report.failedChecks.length} check(s) could not run and '
                    'were left out of the score.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text('Every check', style: theme.textTheme.labelLarge),
                  children: <Widget>[
                    for (final HealthCheck check in report.checks)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(
                          width: 38,
                          child: Text(
                            check.status == HealthStatus.unknown
                                ? '—'
                                : '${check.score}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _healthColor(check.status, theme),
                            ),
                          ),
                        ),
                        title: Text(
                          check.label,
                          style: theme.textTheme.bodySmall,
                        ),
                        subtitle: Text(
                          check.detail,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Color _healthColor(HealthStatus status, ThemeData theme) {
    final bool isDark = theme.brightness == Brightness.dark;
    return switch (status) {
      HealthStatus.healthy => DraisColors.forAttendanceStatus(
        'present',
        isDark: isDark,
      ),
      HealthStatus.degraded => DraisColors.forAttendanceStatus(
        'late',
        isDark: isDark,
      ),
      HealthStatus.critical => DraisColors.forAttendanceStatus(
        'absent',
        isDark: isDark,
      ),
      HealthStatus.unknown => theme.colorScheme.outline,
    };
  }
}

final AutoDisposeFutureProvider<List<AttendanceDevice>>
attendanceDevicesProvider = FutureProvider.autoDispose<List<AttendanceDevice>>((
  Ref ref,
) async {
  final Result<List<AttendanceDevice>> result = await ref
      .watch(timeHealthRepositoryProvider)
      .devices(date: toLocalDateStr());
  return result.fold(
    onOk: (List<AttendanceDevice> list) => list,
    onErr: (Failure failure) => throw failure,
  );
});

/// The school's time policy.
final AutoDisposeFutureProvider<TimePolicy> timePolicyProvider =
    FutureProvider.autoDispose<TimePolicy>((Ref ref) async {
      final Result<TimePolicy> result = await ref
          .watch(timeHealthRepositoryProvider)
          .policy();
      return result.fold(
        onOk: (TimePolicy p) => p,
        onErr: (Failure failure) => throw failure,
      );
    });
