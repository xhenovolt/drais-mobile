import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/features/attendance/presentation/widgets/history_row_tile.dart';
import 'package:drais/features/students/application/students_providers.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/drais_bottom_nav.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// The learner list — the mobile counterpart of the web `/students/list`.
///
/// Same two tabs: **Enrolled** (this term's learners, from
/// `/api/students/enrolled`) and **Admitted** (admitted but not enrolled in
/// the current term, from `/api/students/admitted`). Admission starts here,
/// as on the web.
class StudentsPage extends ConsumerStatefulWidget {
  /// Creates the students page.
  const StudentsPage({this.initialTab = StudentsTab.enrolled, super.key});

  /// The tab to open on — `/students?tab=admitted` from the drawer's
  /// Enroll Student entry.
  final StudentsTab initialTab;

  @override
  ConsumerState<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends ConsumerState<StudentsPage> {
  final TextEditingController _search = TextEditingController();

  late StudentsTab _tab = widget.initialTab;

  @override
  void didUpdateWidget(StudentsPage old) {
    super.didUpdateWidget(old);
    // The branch keeps this state alive, so a later drawer tap arrives as a
    // widget update rather than a fresh page.
    if (old.initialTab != widget.initialTab) _tab = widget.initialTab;
  }
  String? _query;
  int? _classId;

  ({StudentsTab tab, String? search, int? classId}) get _key => (
    tab: _tab,
    search: _query,
    classId: _tab == StudentsTab.enrolled ? _classId : null,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<StudentListResult> list = ref.watch(
      studentListProvider(_key),
    );
    final List<Choice> classes =
        ref.watch(enrollmentOptionsProvider).valueOrNull?.classes ??
        const <Choice>[];

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Students',
        subtitle: list.maybeWhen(
          data: (StudentListResult r) =>
              '${r.rows.length} ${_tab.label.toLowerCase()}'
              '${r.termName == null || r.termName!.isEmpty ? '' : ' · ${r.termName}'}',
          orElse: () => 'Loading…',
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
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Archived learners',
            onPressed: () => context.push(AppRoutes.studentTrash),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(148),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<StudentsTab>(
                  segments: <ButtonSegment<StudentsTab>>[
                    for (final StudentsTab t in StudentsTab.values)
                      ButtonSegment<StudentsTab>(value: t, label: Text(t.label)),
                  ],
                  selected: <StudentsTab>{_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<StudentsTab> s) =>
                      setState(() => _tab = s.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search name or admission number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = null);
                            },
                          ),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (String value) => setState(
                    () => _query = value.trim().isEmpty ? null : value.trim(),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: _tab == StudentsTab.admitted
                    ? const SizedBox.shrink()
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: const Text('All classes'),
                              selected: _classId == null,
                              onSelected: (_) => setState(() => _classId = null),
                            ),
                          ),
                          for (final Choice c in classes)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(c.label),
                                selected: _classId == c.id,
                                onSelected: (_) => setState(
                                  () => _classId = _classId == c.id ? null : c.id,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: DraisBottomNav.reservedHeight - 56),
        child: FloatingActionButton.extended(
          onPressed: () => context.push(AppRoutes.admitStudent),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Admit'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(studentListProvider(_key));
          await ref.read(studentListProvider(_key).future);
        },
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => ErrorView(
            title: 'Could not load students',
            message: error is Failure
                ? error.message
                : 'Something went wrong reading the roster.',
            onRetry: () => ref.invalidate(studentListProvider(_key)),
          ),
          data: (StudentListResult r) => _list(context, r),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, StudentListResult r) {
    final ThemeData theme = Theme.of(context);
    if (r.rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: <Widget>[
          Icon(
            Icons.person_search_outlined,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            _query != null || _classId != null
                ? 'No learners match that'
                : _tab == StudentsTab.enrolled
                ? 'Nobody is enrolled in this term yet'
                : 'Everyone admitted is enrolled this term',
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        16,
        12,
        16,
        DraisBottomNav.reservedHeight + 56,
      ),
      itemCount: r.rows.length + (r.truncated ? 1 : 0),
      separatorBuilder: (BuildContext context, int _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int i) {
        if (i == r.rows.length) {
          return Text(
            'Showing the first 10,000 learners. Search to narrow the list.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          );
        }
        return _StudentRow(row: r.rows[i], tab: _tab);
      },
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.row, required this.tab});

  final StudentListRow row;
  final StudentsTab tab;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String line = <String>[
      if (row.className != null) row.className!,
      if (row.streamName != null) row.streamName!,
      // Said plainly: a missing admission number is fixable data.
      row.admissionNo ?? 'No admission number',
    ].join(' · ');

    return Card(
      child: InkWell(
        onTap: () => context.go(AppRoutes.studentDetailPath(row.id)),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              PersonAvatar(initials: row.initials, photoUrl: row.photoUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      row.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (tab == StudentsTab.admitted)
                TextButton(
                  onPressed: () =>
                      context.push(AppRoutes.enrollStudentPath(row.id)),
                  child: const Text('Enrol'),
                )
              else
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
