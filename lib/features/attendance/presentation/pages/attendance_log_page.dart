import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/features/attendance/application/attendance_log_controller.dart';
import 'package:drais/features/attendance/domain/entities/attendance_history.dart';
import 'package:drais/features/attendance/domain/entities/attendance_insights.dart';
import 'package:drais/features/attendance/presentation/widgets/history_row_tile.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/drais_bottom_nav.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// The attendance logs — the mobile counterpart of the web
/// `/attendance/logs` page.
///
/// Same data, same tabs (All / Learners / Staff / Unmatched, each with its
/// count), same filters (date presets, time of day, arrival status, gender,
/// residence, class, search) and same sort keys. The web page's write actions
/// — clearing logs, deleting rows, correcting identities and clocks — are not
/// here yet; see `docs/ROADMAP.md`.
class AttendanceLogPage extends ConsumerStatefulWidget {
  /// Creates the attendance log page.
  const AttendanceLogPage({super.key});

  @override
  ConsumerState<AttendanceLogPage> createState() => _AttendanceLogPageState();
}

class _AttendanceLogPageState extends ConsumerState<AttendanceLogPage> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

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
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load ahead of the edge so the list does not visibly stall.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      ref.read(attendanceLogControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AttendanceLogState state = ref.watch(attendanceLogControllerProvider);
    final AttendanceLogController controller = ref.read(
      attendanceLogControllerProvider.notifier,
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Attendance logs',
        subtitle:
            '${_rangeLabel(state.query)} · ${state.total} '
            'punch${state.total == 1 ? '' : 'es'}',
        busy: state.isLoading && state.rows.isNotEmpty,
        accentStrip: state.hasClockConcerns
            ? DraisColors.forAttendanceStatus('late', isDark: false)
            : null,
        actions: <Widget>[
          IconButton(
            icon: Badge(
              isLabelVisible: state.query.hasExtraFilters,
              smallSize: 8,
              child: const Icon(Icons.tune),
            ),
            tooltip: 'Filters',
            onPressed: () => _openFilters(context),
          ),
          _SortMenu(query: state.query, controller: controller),
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
        bottom: _Header(state: state, controller: controller),
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: _body(state, controller),
      ),
    );
  }

  Widget _body(AttendanceLogState state, AttendanceLogController controller) {
    final Failure? failure = state.failure;
    if (failure != null && state.rows.isEmpty && !state.isLoading) {
      return ErrorView.fromFailure(
        failure,
        onRetry: controller.load,
        environment: ref.read(appConfigProvider).environment,
      );
    }

    final bool multiDay = !state.query.isSingleDay;

    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        DraisBottomNav.reservedHeight,
      ),
      itemCount: state.rows.length + 3,
      itemBuilder: (BuildContext context, int i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name or PIN',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: state.query.search == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _search.clear();
                          controller.setSearch(null);
                        },
                      ),
              ),
              onSubmitted: controller.setSearch,
            ),
          );
        }
        if (i == 1) {
          return _SummaryBlock(state: state, controller: controller);
        }
        if (i == state.rows.length + 2) {
          if (state.isLoading && state.rows.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.isEmpty) return const _EmptyResult();
          return const SizedBox.shrink();
        }

        final AttendanceHistoryRow row = state.rows[i - 2];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: HistoryRowTile(
            row: row,
            offsetMinutes: state.offsetMinutes,
            showDate: multiDay,
            onTap: row.personId == null || row.roleType == null
                ? null
                : () => context.push(
                    AppRoutes.attendancePersonPath(
                      row.personId!,
                      role: row.roleType!,
                      name: row.personName,
                    ),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _openFilters(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => const _FilterSheet(),
  );
}

String _rangeLabel(AttendanceHistoryQuery q) {
  if (q.dateFrom == null && q.dateTo == null) return 'All time';
  if (q.isSingleDay) return describeLocalDate(q.dateFrom!);
  return '${q.dateFrom == null ? '…' : describeLocalDate(q.dateFrom!)} – '
      '${q.dateTo == null ? '…' : describeLocalDate(q.dateTo!)}';
}

/// Date bar and tabs, docked under the app bar.
class _Header extends StatelessWidget implements PreferredSizeWidget {
  const _Header({required this.state, required this.controller});

  final AttendanceLogState state;
  final AttendanceLogController controller;

  @override
  Size get preferredSize => const Size.fromHeight(96);

  @override
  Widget build(BuildContext context) {
    final AttendanceHistoryQuery q = state.query;
    final bool single = q.isSingleDay;
    final bool atToday = single && isToday(q.dateFrom!);

    return SizedBox(
      height: 96,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 48,
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous day',
                  onPressed: single ? () => controller.shiftDay(-1) : null,
                ),
                Expanded(
                  child: Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: Text(_rangeLabel(q)),
                      onPressed: () => _pickRange(context),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next day',
                  // Never step into the future.
                  onPressed: single && !atToday
                      ? () => controller.shiftDay(1)
                      : null,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                for (final HistoryTab tab in HistoryTab.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 6),
                    child: ChoiceChip(
                      label: Text('${tab.label} ${state.tabCounts.of(tab)}'),
                      selected: q.tab == tab,
                      onSelected: (_) => controller.setTab(tab),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange(BuildContext context) async {
    final Object? choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final DatePreset p in DatePreset.values)
              ListTile(
                title: Text(p.label),
                onTap: () => Navigator.of(context).pop(p),
              ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Custom range…'),
              onTap: () => Navigator.of(context).pop('custom'),
            ),
          ],
        ),
      ),
    );
    if (choice is DatePreset) {
      await controller.applyPreset(choice);
    } else if (choice == 'custom' && context.mounted) {
      final DateTime now = DateTime.now();
      final DateTimeRange? range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
      );
      if (range != null) {
        await controller.setRange(
          toLocalDateStr(range.start),
          toLocalDateStr(range.end),
        );
      }
    }
  }
}

/// Day counts (single-day ranges), notices, and active filter chips.
class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({required this.state, required this.controller});

  final AttendanceLogState state;
  final AttendanceLogController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final DashboardAttendanceCounts? counts = state.counts;
    final int unmatched = state.tabCounts.unmatched;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (counts != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: <Widget>[
                    AttendanceCountsRow(
                      title: 'Learners',
                      counts: counts.students,
                    ),
                    const Divider(height: 20),
                    AttendanceCountsRow(title: 'Staff', counts: counts.staff),
                  ],
                ),
              ),
            ),
          if (unmatched > 0 && state.query.tab != HistoryTab.unmatched)
            _Notice(
              icon: Icons.person_search_outlined,
              color: DraisColors.forAttendanceStatus('half_day', isDark: isDark),
              text:
                  '$unmatched punch${unmatched == 1 ? '' : 'es'} could not be '
                  'matched to a person.',
              onTap: () => controller.setTab(HistoryTab.unmatched),
            ),
          if (state.hasClockConcerns)
            _Notice(
              icon: Icons.schedule_outlined,
              color: DraisColors.forAttendanceStatus('late', isDark: isDark),
              text:
                  'A device clock is out by more than a minute. Arrival times '
                  'in this range may not be accurate.',
            ),
          if (state.query.hasExtraFilters) _ActiveFilters(state: state),
        ],
      ),
    );
  }
}

/// Present / late / absent / total for one role — the dashboard block.
class AttendanceCountsRow extends StatelessWidget {
  /// Creates a counts row.
  const AttendanceCountsRow({
    required this.title,
    required this.counts,
    this.large = false,
    super.key,
  });

  /// `Learners` or `Staff`.
  final String title;

  /// The counts.
  final RoleCounts counts;

  /// Bigger figures, for the home card.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    Widget stat(String label, int value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$value',
            style:
                (large
                        ? theme.textTheme.headlineMedium
                        : theme.textTheme.titleLarge)
                    ?.copyWith(color: color, fontWeight: FontWeight.w700),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$title · ${counts.total} on roll',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            stat(
              'Present',
              counts.present,
              DraisColors.forAttendanceStatus('present', isDark: isDark),
            ),
            stat(
              'Late',
              counts.late,
              DraisColors.forAttendanceStatus('late', isDark: isDark),
            ),
            stat(
              'Absent',
              counts.absent,
              DraisColors.forAttendanceStatus('absent', isDark: isDark),
            ),
          ],
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.text,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
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
            if (onTap != null)
              Icon(Icons.chevron_right, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}

/// Removable chips for each active filter.
class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.state});

  final AttendanceLogState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AttendanceHistoryQuery q = state.query;
    final AttendanceLogController c = ref.read(
      attendanceLogControllerProvider.notifier,
    );
    final List<ClassOption> classes =
        ref.watch(attendanceClassesProvider).valueOrNull ??
        const <ClassOption>[];
    String className(int id) => classes
        .firstWhere(
          (ClassOption o) => o.id == id,
          orElse: () => ClassOption(id: id, name: 'Class #$id'),
        )
        .name;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          if (q.timeframe != HistoryTimeframe.all)
            InputChip(
              label: Text(q.timeframe.label),
              onDeleted: () => c.setTimeframe(HistoryTimeframe.all),
            ),
          if (q.derived != DerivedFilter.none)
            InputChip(
              label: Text(q.derived.label),
              onDeleted: () => c.setDerived(DerivedFilter.none),
            ),
          if (q.gender != null)
            InputChip(
              label: Text(q.gender == 'male' ? 'Male' : 'Female'),
              onDeleted: () => c.setGender(null),
            ),
          if (q.residence != null)
            InputChip(
              label: Text(q.residence == 'day' ? 'Day scholars' : 'Boarders'),
              onDeleted: () => c.setResidence(null),
            ),
          if (q.classId != null)
            InputChip(
              label: Text(className(q.classId!)),
              onDeleted: () => c.setClass(null),
            ),
          ActionChip(label: const Text('Clear all'), onPressed: c.clearFilters),
        ],
      ),
    );
  }
}

/// The web page's sortable columns.
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.query, required this.controller});

  final AttendanceHistoryQuery query;
  final AttendanceLogController controller;

  @override
  Widget build(BuildContext context) => PopupMenuButton<HistorySort>(
    icon: const Icon(Icons.sort),
    tooltip: 'Sort',
    onSelected: (HistorySort sort) => controller.setSort(
      sort,
      // Choosing the active column again flips the direction.
      ascending: sort == query.sort ? !query.ascending : false,
    ),
    itemBuilder: (BuildContext context) => <PopupMenuEntry<HistorySort>>[
      for (final HistorySort s in HistorySort.values)
        PopupMenuItem<HistorySort>(
          value: s,
          child: Row(
            children: <Widget>[
              Expanded(child: Text(s.label)),
              if (s == query.sort)
                Icon(
                  query.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                ),
            ],
          ),
        ),
    ],
  );
}

/// Every filter the web logs page offers.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AttendanceHistoryQuery q = ref
        .watch(attendanceLogControllerProvider)
        .query;
    final AttendanceLogController c = ref.read(
      attendanceLogControllerProvider.notifier,
    );
    final AsyncValue<List<ClassOption>> classes = ref.watch(
      attendanceClassesProvider,
    );

    Widget section(String title, List<Widget> chips) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            section('Arrival', <Widget>[
              for (final DerivedFilter d in DerivedFilter.values)
                ChoiceChip(
                  label: Text(d.label),
                  selected: q.derived == d,
                  onSelected: (_) => c.setDerived(d),
                ),
            ]),
            section('Time of day', <Widget>[
              for (final HistoryTimeframe t in HistoryTimeframe.values)
                ChoiceChip(
                  label: Text(t.label),
                  selected: q.timeframe == t,
                  onSelected: (_) => c.setTimeframe(t),
                ),
            ]),
            section('Gender', <Widget>[
              ChoiceChip(
                label: const Text('Any'),
                selected: q.gender == null,
                onSelected: (_) => c.setGender(null),
              ),
              ChoiceChip(
                label: const Text('Male'),
                selected: q.gender == 'male',
                onSelected: (_) => c.setGender('male'),
              ),
              ChoiceChip(
                label: const Text('Female'),
                selected: q.gender == 'female',
                onSelected: (_) => c.setGender('female'),
              ),
            ]),
            section('Residence', <Widget>[
              ChoiceChip(
                label: const Text('Any'),
                selected: q.residence == null,
                onSelected: (_) => c.setResidence(null),
              ),
              ChoiceChip(
                label: const Text('Day scholars'),
                selected: q.residence == 'day',
                onSelected: (_) => c.setResidence('day'),
              ),
              ChoiceChip(
                label: const Text('Boarders'),
                selected: q.residence == 'boarding',
                onSelected: (_) => c.setResidence('boarding'),
              ),
            ]),
            Text('Class', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            classes.when(
              data: (List<ClassOption> list) => DropdownButtonFormField<int?>(
                initialValue: q.classId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(child: Text('All classes')),
                  for (final ClassOption o in list)
                    DropdownMenuItem<int?>(value: o.id, child: Text(o.name)),
                ],
                onChanged: c.setClass,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (Object _, StackTrace _) => Text(
                'Classes could not be loaded.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: c.clearFilters,
                  child: const Text('Clear filters'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

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
          Text('No punches match', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            // Says what it usually means rather than just what is missing.
            'Nothing was recorded for these filters. On a school day with no '
            'filters, this usually means the attendance devices did not '
            'report.',
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
