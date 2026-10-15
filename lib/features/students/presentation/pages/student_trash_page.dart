import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/application/students_providers.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// Archived learners, with restore — the web `/students/trash`.
///
/// Permanent deletion is not offered: on the platform it requires a
/// super-admin and an explicit confirmation step, and it is irreversible.
/// That belongs at a desk.
class StudentTrashPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const StudentTrashPage({super.key});

  @override
  ConsumerState<StudentTrashPage> createState() => _StudentTrashPageState();
}

class _StudentTrashPageState extends ConsumerState<StudentTrashPage> {
  String? _search;
  final Set<int> _busy = <int>{};

  Future<void> _restore(TrashedStudent s) async {
    setState(() => _busy.add(s.id));
    final Result<int> result = await ref
        .read(studentsRepositoryProvider)
        .restore(<int>[s.id]);
    if (!mounted) return;
    setState(() => _busy.remove(s.id));
    final String message = switch (result) {
      Ok<int>(:final int value) =>
        value == 0 ? '${s.name} was already restored' : '${s.name} restored',
      Err<int>(:final Failure failure) => failure.message,
    };
    if (result is Ok<int>) {
      ref
        ..invalidate(studentTrashProvider)
        ..invalidate(studentListProvider);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<TrashedStudent>> trash = ref.watch(
      studentTrashProvider(_search),
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Archived learners',
        subtitle: trash.maybeWhen(
          data: (List<TrashedStudent> l) => '${l.length} in Trash',
          orElse: () => null,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search name or admission number',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (String v) =>
                  setState(() => _search = v.trim().isEmpty ? null : v.trim()),
            ),
          ),
        ),
      ),
      body: trash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => ErrorView(
          title: 'Could not load Trash',
          message: e is Failure ? e.message : 'Something went wrong.',
          onRetry: () => ref.invalidate(studentTrashProvider(_search)),
        ),
        data: (List<TrashedStudent> list) => list.isEmpty
            ? Center(
                child: Text('Trash is empty', style: theme.textTheme.titleSmall),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (BuildContext context, int _) =>
                    const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int i) {
                  final TrashedStudent s = list[i];
                  return Card(
                    child: ListTile(
                      title: Text(s.name.isEmpty ? 'Unnamed learner' : s.name),
                      subtitle: Text(
                        <String?>[
                          s.admissionNo,
                          if (s.deletedAt != null)
                            'archived ${s.deletedAt!.split(' ').first}',
                          s.deleteReason,
                          '${s.enrollmentCount} enrolments',
                        ].whereType<String>().join(' · '),
                      ),
                      trailing: _busy.contains(s.id)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              onPressed: () => _restore(s),
                              child: const Text('Restore'),
                            ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
