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

/// Punches DRAIS could not attach to anyone.
///
/// ## Why these are not lost
///
/// `attendance_raw_events` is append-only. A punch that could not be resolved
/// to a person is still recorded, with whatever label the device supplied.
/// That is what makes a claim possible weeks later: the engine re-derives the
/// day from raw events, so attaching an identity now retroactively fixes the
/// register then. Discarding unresolved punches would have thrown that away.
///
/// ## Why claiming is not offered here
///
/// Claiming attaches a person and then **recomputes the day** through the rule
/// evaluator — roughly 5,000 lines of decision logic plus the device-clock
/// policies. Direct mode has no engine to call, so a claim made here would
/// attach an identity and leave the verdict stale: the punch would look
/// resolved while the register still showed the learner absent. That is worse
/// than not offering it.
///
/// Until claiming can trigger a real re-evaluation, this screen does the half
/// that is honest — it finds them, shows what is known, and says where the fix
/// happens.
class UnmatchedPunchesPage extends ConsumerWidget {
  /// Creates the unmatched punches page.
  const UnmatchedPunchesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<UnmatchedPunch>> punches = ref.watch(
      unmatchedPunchesProvider,
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Unidentified punches',
        subtitle: punches.maybeWhen(
          data: (List<UnmatchedPunch> list) => list.isEmpty
              ? 'Nothing outstanding'
              : '${list.length} in the last 90 days',
          orElse: () => 'Loading…',
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(unmatchedPunchesProvider),
          ),
        ],
      ),
      body: punches.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => ErrorView(
          title: 'Could not load unidentified punches',
          message: error is Failure ? error.message : 'Something went wrong.',
          onRetry: () => ref.invalidate(unmatchedPunchesProvider),
        ),
        data: (List<UnmatchedPunch> list) {
          if (list.isEmpty) return const _AllResolved();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              const _Explainer(),
              const SizedBox(height: 12),
              ...list.map(
                (UnmatchedPunch p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PunchCard(punch: p),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.person_search_outlined,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Someone scanned, but DRAIS could not tell who',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'These punches are kept, not discarded. Claiming one on the web '
              'app attaches the learner and recomputes that day, so their '
              'register is corrected retroactively.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PunchCard extends StatelessWidget {
  const _PunchCard({required this.punch});

  final UnmatchedPunch punch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  formatClockTime(punch.punchAt),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                Text(
                  describeLocalDate(toLocalDateStr(punch.punchAt)),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    // A device label is the single most useful clue here — it
                    // is usually the name typed in when the finger was
                    // enrolled, which is exactly who this is.
                    punch.hasNameHint
                        ? punch.displayName!
                        : 'No name from the device',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: punch.hasNameHint
                          ? FontWeight.w600
                          : FontWeight.w400,
                      fontStyle: punch.hasNameHint ? null : FontStyle.italic,
                      color: punch.hasNameHint
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      DraisPill(
                        label: punch.source,
                        color: theme.colorScheme.onSurfaceVariant,
                        icon: Icons.sensors,
                      ),
                      if (punch.hasNameHint)
                        DraisPill(
                          label: 'Name on device',
                          color: DraisColors.forAttendanceStatus(
                            'present',
                            isDark: isDark,
                          ),
                          icon: Icons.lightbulb_outline,
                        ),
                      if (punch.resolutionPath != null)
                        DraisPill(
                          label: punch.resolutionPath!,
                          color: DraisColors.forAttendanceStatus(
                            'half_day',
                            isDark: isDark,
                          ),
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

class _AllResolved extends StatelessWidget {
  const _AllResolved();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.verified_outlined,
              size: 48,
              color: DraisColors.forAttendanceStatus('present', isDark: isDark),
            ),
            const SizedBox(height: 16),
            Text(
              'Every punch is identified',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'No unidentified scans in the last 90 days. Every punch has been '
              'attached to a learner or a staff member.',
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

/// Punches with no person attached.
final AutoDisposeFutureProvider<List<UnmatchedPunch>> unmatchedPunchesProvider =
    FutureProvider.autoDispose<List<UnmatchedPunch>>((Ref ref) async {
      final Result<List<UnmatchedPunch>> result = await ref
          .watch(attendanceRepositoryProvider)
          .unmatchedPunches();
      return result.fold(
        onOk: (List<UnmatchedPunch> list) => list,
        onErr: (Failure failure) => throw failure,
      );
    });
