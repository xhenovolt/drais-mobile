import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/domain/student_summary.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/drais_bottom_nav.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// The learner roster.
///
/// Who is enrolled, which class they are in, and — because this is an
/// attendance system — whether they turned up today. That last column is why
/// the screen is worth opening rather than being a list of names.
///
/// ## Adding learners is deliberately not here
///
/// Admission and enrolment are long, validation-heavy flows done once per
/// learner at a desk, and they already exist in the web app. Rebuilding them
/// for a phone would be a lot of work to make a worse version of something a
/// registrar does sitting down. This screen finds and inspects; the web app
/// admits.
class StudentsPage extends ConsumerStatefulWidget {
  /// Creates the students page.
  const StudentsPage({super.key});

  @override
  ConsumerState<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends ConsumerState<StudentsPage> {
  final TextEditingController _search = TextEditingController();

  String? _className;
  String? _query;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<StudentSummary>> students = ref.watch(
      studentsProvider(StudentsQuery(search: _query, className: _className)),
    );
    final AsyncValue<List<String>> classes = ref.watch(studentClassesProvider);

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Students',
        subtitle: students.maybeWhen(
          data: (List<StudentSummary> list) =>
              '${list.length} shown${_className == null ? '' : ' · $_className'}',
          orElse: () => 'Loading…',
        ),
        leading: Builder(
          builder: (BuildContext context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: Scaffold.of(context).openDrawer,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: <Widget>[
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
                child: classes.maybeWhen(
                  data: (List<String> names) => ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: const Text('All classes'),
                          selected: _className == null,
                          onSelected: (_) => setState(() => _className = null),
                        ),
                      ),
                      ...names.map(
                        (String name) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(name),
                            selected: _className == name,
                            onSelected: (_) => setState(
                              () =>
                                  _className = _className == name ? null : name,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
      body: students.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => ErrorView(
          title: 'Could not load students',
          message: error is Failure
              ? error.message
              : 'Something went wrong reading the roster.',
          onRetry: () => ref.invalidate(studentsProvider),
        ),
        data: (List<StudentSummary> list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.person_search_outlined,
                      size: 44,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _query == null && _className == null
                          ? 'No learners enrolled'
                          : 'No learners match that',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              DraisBottomNav.reservedHeight,
            ),
            itemCount: list.length,
            separatorBuilder: (BuildContext context, int _) =>
                const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int i) =>
                _StudentRow(student: list[i]),
          );
        },
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student});

  final StudentSummary student;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: () => context.go(AppRoutes.studentDetailPath(student.id)),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  student.initials,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      student.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (student.className != null) student.className!,
                        // Say so plainly rather than leaving a gap — a missing
                        // admission number is a data problem someone can fix.
                        student.admissionNo ?? 'No admission number',
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
              const SizedBox(width: 8),
              AttendanceStatusPill(student.todayStatus),
              const SizedBox(width: 4),
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

/// Filters for the roster.
class StudentsQuery {
  /// Creates a query.
  const StudentsQuery({this.search, this.className});

  /// Free-text match on name or admission number.
  final String? search;

  /// Restrict to one class.
  final String? className;

  @override
  bool operator ==(Object other) =>
      other is StudentsQuery &&
      other.search == search &&
      other.className == className;

  @override
  int get hashCode => Object.hash(search, className);
}

/// The roster for a query, with today's attendance attached.
final AutoDisposeFutureProviderFamily<List<StudentSummary>, StudentsQuery>
studentsProvider = FutureProvider.autoDispose
    .family<List<StudentSummary>, StudentsQuery>((
      Ref ref,
      StudentsQuery q,
    ) async {
      final Result<List<StudentSummary>> result = await ref
          .watch(studentsRepositoryProvider)
          .list(
            search: q.search,
            className: q.className,
            attendanceDate: toLocalDateStr(),
          );

      return result.fold(
        onOk: (List<StudentSummary> list) => list,
        onErr: (Failure failure) => throw failure,
      );
    });

/// Class names for the filter row.
final AutoDisposeFutureProvider<List<String>> studentClassesProvider =
    FutureProvider.autoDispose<List<String>>((Ref ref) async {
      final Result<List<String>> result = await ref
          .watch(studentsRepositoryProvider)
          .classes();
      return result.fold(
        onOk: (List<String> names) => names,
        onErr: (Failure failure) => throw failure,
      );
    });
