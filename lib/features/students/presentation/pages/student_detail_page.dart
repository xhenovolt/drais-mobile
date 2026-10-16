import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/attendance/presentation/widgets/history_row_tile.dart';
import 'package:drais/features/students/application/students_providers.dart';
import 'package:drais/features/students/domain/entities/student_admin.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/features/students/presentation/pages/student_admin_pages.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// One learner — the mobile counterpart of the web `/students/[id]`, built on
/// the same `GET /api/students/[id]/profile`.
///
/// Attendance is one tap away on the per-person attendance screen, which
/// carries the platform's own behavioural profile rather than a figure
/// computed here.
class StudentDetailPage extends ConsumerWidget {
  /// Creates the detail page.
  const StudentDetailPage({required this.studentId, super.key});

  /// `students.id`.
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StudentProfile> profile = ref.watch(
      studentProfileProvider(studentId),
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: profile.maybeWhen(
          data: (StudentProfile p) => p.row.displayName,
          orElse: () => 'Learner',
        ),
        subtitle: profile.maybeWhen(
          data: (StudentProfile p) => <String>[
            if (p.activeEnrollment?.className != null)
              p.activeEnrollment!.className!,
            p.row.admissionNo ?? 'No admission number',
          ].join(' · '),
          orElse: () => null,
        ),
        actions: <Widget>[
          if (profile.valueOrNull != null)
            _ActionsMenu(profile: profile.valueOrNull!),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => ErrorView(
          title: 'Could not load this learner',
          message: error is Failure ? error.message : 'Something went wrong.',
          onRetry: () => ref.invalidate(studentProfileProvider(studentId)),
        ),
        data: (StudentProfile p) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(studentProfileProvider(studentId));
            await ref.read(studentProfileProvider(studentId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: <Widget>[
              _IdentityCard(profile: p),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Attendance'),
                      onPressed: () => context.push(
                        AppRoutes.attendancePersonPath(
                          p.row.personId,
                          role: 'student',
                          name: p.row.displayName,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.how_to_reg_outlined),
                      label: Text(
                        p.activeEnrollment == null ? 'Enrol' : 'Change class',
                      ),
                      onPressed: () =>
                          context.push(AppRoutes.enrollStudentPath(studentId)),
                    ),
                  ),
                ],
              ),
              if (ref.watch(canProvider('finance.view'))) ...<Widget>[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Fees & payments'),
                  onPressed: () => context.push(
                    AppRoutes.learnerFinancePath(
                      p.row.id,
                      name: p.row.displayName,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _Section(
                title: 'Family',
                children: <Widget>[
                  _Field(label: 'Guardian', value: p.guardianName),
                  _Field(label: 'Guardian contact', value: p.guardianContact),
                  _Field(label: 'Father', value: p.fatherName),
                  _Field(label: 'Father status', value: p.fatherStatus),
                  _Field(label: 'Father contact', value: p.fatherContact),
                  _Field(label: 'Orphan status', value: p.orphanStatus),
                ],
              ),
              if (p.parents.isNotEmpty)
                _Section(
                  title: 'Parents',
                  children: p.parents.map(_RelationTile.new).toList(),
                ),
              _Section(
                title: 'Contacts',
                children: <Widget>[
                  for (final StudentRelation c in p.contacts)
                    InkWell(
                      onTap: c.contactId == null
                          ? null
                          : () => showContactSheet(
                              context,
                              ref,
                              contactId: c.contactId,
                              initial: ContactRow(
                                studentId: p.row.id,
                                contactId: c.contactId!,
                                firstName: c.firstName,
                                lastName: c.lastName,
                                phone: c.phone,
                                email: c.email,
                                address: c.address,
                                occupation: c.occupation,
                                relationship: c.relationship,
                                aliveStatus: c.aliveStatus,
                                isPrimary: c.isPrimary,
                              ),
                            ),
                      child: _RelationTile(c),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add contact'),
                      onPressed: () =>
                          showContactSheet(context, ref, studentId: p.row.id),
                    ),
                  ),
                ],
              ),
              if (p.nextOfKin.isNotEmpty)
                _Section(
                  title: 'Next of kin',
                  children: p.nextOfKin.map(_RelationTile.new).toList(),
                ),
              _Section(
                title: 'Background',
                children: <Widget>[
                  _Field(label: 'Place of birth', value: p.placeOfBirth),
                  _Field(label: 'Residence', value: p.placeOfResidence),
                  _Field(label: 'District', value: p.district),
                  _Field(label: 'Nationality', value: p.nationality),
                  _Field(label: 'Previous school', value: p.previousSchool),
                  _Field(label: 'Notes', value: p.notes),
                  _Field(label: 'Documents', value: '${p.documentCount}'),
                  _Field(
                    label: 'Fingerprints',
                    value:
                        '${p.fingerprintsActive} active of ${p.fingerprintsTotal}',
                  ),
                ],
              ),
              _Section(
                title: 'Enrolment history',
                children: p.enrollments.isEmpty
                    ? <Widget>[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text('Never enrolled.'),
                        ),
                      ]
                    : p.enrollments.map(_EnrollmentTile.new).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Action { edit, profile, nextOfKin, status, residency, archive }

/// What can be done to a learner. Items needing a permission are hidden from
/// users without it; the repository re-checks, as the server would.
class _ActionsMenu extends ConsumerWidget {
  const _ActionsMenu({required this.profile});

  final StudentProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool canProfile = ref.watch(canProvider('learners.profile.update'));
    final bool canResidency = ref.watch(
      canProvider('academics.residency.manage'),
    );
    final int id = profile.row.id;

    return PopupMenuButton<_Action>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Actions',
      onSelected: (_Action a) async {
        switch (a) {
          case _Action.edit:
            await context.push(AppRoutes.editStudentPath(id));
          case _Action.profile:
            await context.push(AppRoutes.editStudentProfilePath(id));
          case _Action.nextOfKin:
            await context.push(AppRoutes.nextOfKinPath(id));
          case _Action.status:
            await _changeStatus(context, ref);
          case _Action.residency:
            await _changeResidency(context, ref);
          case _Action.archive:
            await _archive(context, ref);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_Action>>[
        const PopupMenuItem<_Action>(
          value: _Action.edit,
          child: Text('Edit details'),
        ),
        if (canProfile) ...const <PopupMenuEntry<_Action>>[
          PopupMenuItem<_Action>(
            value: _Action.profile,
            child: Text('Family & background'),
          ),
          PopupMenuItem<_Action>(
            value: _Action.nextOfKin,
            child: Text('Next of kin'),
          ),
        ],
        const PopupMenuItem<_Action>(
          value: _Action.status,
          child: Text('Change status'),
        ),
        if (canResidency)
          const PopupMenuItem<_Action>(
            value: _Action.residency,
            child: Text('Day / boarding'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<_Action>(
          value: _Action.archive,
          child: Text('Archive to Trash'),
        ),
      ],
    );
  }

  void _report(BuildContext context, WidgetRef ref, Result<Object?> r, String ok) {
    if (!context.mounted) return;
    if (r is Ok<Object?>) {
      ref
        ..invalidate(studentProfileProvider(profile.row.id))
        ..invalidate(studentListProvider);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (r) {
          Ok<Object?>() => ok,
          Err<Object?>(:final Failure failure) => failure.message,
        }),
      ),
    );
  }

  Future<void> _changeStatus(BuildContext context, WidgetRef ref) async {
    StudentStatus? chosen = StudentStatus.fromWire(profile.row.studentStatus);
    final TextEditingController reason = TextEditingController();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter set) => AlertDialog(
          title: const Text('Change status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final StudentStatus s in StudentStatus.values)
                    ChoiceChip(
                      label: Text(s.label),
                      selected: chosen == s,
                      onSelected: (_) => set(() => chosen = s),
                    ),
                ],
              ),
              if (chosen == StudentStatus.left) ...<Widget>[
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason for leaving *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: chosen == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final String why = reason.text;
    reason.dispose();
    if (go != true || chosen == null || !context.mounted) return;
    final Result<String> r = await ref
        .read(studentsRepositoryProvider)
        .setStatus(profile.row.id, chosen!, reason: why);
    if (context.mounted) _report(context, ref, r, 'Status updated');
  }

  Future<void> _changeResidency(BuildContext context, WidgetRef ref) async {
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Residency'),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('day'),
            child: const Text('Day scholar'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('boarding'),
            child: const Text('Boarder'),
          ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    final Result<void> r = await ref
        .read(studentsRepositoryProvider)
        .setResidency(profile.row.id, picked);
    if (context.mounted) _report(context, ref, r, 'Residency updated');
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final TextEditingController reason = TextEditingController();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Archive ${profile.row.displayName}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'The learner moves to Trash and stops being recognised on '
              'attendance devices. Nothing is deleted; they can be restored.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    final String why = reason.text;
    reason.dispose();
    if (go != true || !context.mounted) return;
    final Result<void> r = await ref
        .read(studentsRepositoryProvider)
        .archive(profile.row.id, reason: why);
    if (!context.mounted) return;
    if (r is Ok<void>) {
      ref
        ..invalidate(studentListProvider)
        ..invalidate(studentTrashProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student archived successfully.')),
      );
      context.pop();
    } else {
      _report(context, ref, r, '');
    }
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.profile});

  final StudentProfile profile;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StudentListRow s = profile.row;
    final EnrollmentRecord? active = profile.activeEnrollment;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                PersonAvatar(
                  initials: s.initials,
                  photoUrl: s.photoUrl,
                  radius: 32,
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
                          if (active?.className != null)
                            DraisPill(
                              label: active!.className!,
                              color: theme.colorScheme.primary,
                              icon: Icons.class_outlined,
                            ),
                          if (s.studentStatus != null &&
                              s.studentStatus != 'active')
                            DraisPill(
                              label: s.studentStatus!,
                              color: theme.colorScheme.error,
                            ),
                          if (s.residencyStatus != null)
                            DraisPill(
                              label: s.residencyStatus == 'boarding'
                                  ? 'Boarder'
                                  : 'Day scholar',
                              color: theme.colorScheme.onSurfaceVariant,
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
            _Field(label: 'Admitted', value: s.admissionDate?.split(' ').first),
            _Field(label: 'Gender', value: s.gender),
            _Field(label: 'Date of birth', value: s.dateOfBirth?.split(' ').first),
            _Field(label: 'Phone', value: s.phone),
            _Field(label: 'Email', value: s.email),
            if (active != null) ...<Widget>[
              _Field(label: 'Term', value: active.termName),
              _Field(label: 'Stream', value: active.streamName),
              _Field(label: 'Program', value: active.programName),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class _RelationTile extends StatelessWidget {
  const _RelationTile(this.relation);

  final StudentRelation relation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String detail = <String?>[
      relation.relationship,
      relation.phone,
      relation.email,
      relation.occupation,
    ].whereType<String>().where((String s) => s.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(relation.name, style: theme.textTheme.bodyMedium),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (relation.isPrimary)
            DraisPill(label: 'Primary', color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

class _EnrollmentTile extends StatelessWidget {
  const _EnrollmentTile(this.e);

  final EnrollmentRecord e;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = e.status == 'active';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  <String?>[e.className, e.streamName]
                      .whereType<String>()
                      .join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: active ? FontWeight.w600 : null,
                  ),
                ),
                Text(
                  <String?>[
                    e.termName,
                    e.academicYearName,
                    e.programName,
                    e.enrollmentType,
                  ].whereType<String>().join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          DraisPill(
            label: e.status ?? '—',
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ],
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
              // "Not recorded" rather than a blank, which looks like a bug.
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
