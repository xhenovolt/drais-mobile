import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/application/students_providers.dart';
import 'package:drais/features/students/domain/entities/student_admin.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/features/students/presentation/widgets/choice_picker.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

void _snack(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

String _messageOf(Object e) =>
    e is Failure ? e.message : 'Something went wrong.';

// ─────────────────────────────────────────────────────────────────────────
// Add / edit a contact
// ─────────────────────────────────────────────────────────────────────────

/// Opens the contact form. With [contactId] it edits that contact; with
/// [studentId] alone it adds a contact to that learner. Returns true when
/// something was saved or removed.
Future<bool> showContactSheet(
  BuildContext context,
  WidgetRef ref, {
  int? studentId,
  int? contactId,
  ContactRow? initial,
}) async {
  final bool? done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _ContactForm(
        studentId: studentId,
        contactId: contactId,
        initial: initial,
      ),
    ),
  );
  if (done ?? false) {
    ref
      ..invalidate(contactsProvider)
      ..invalidate(studentProfileProvider);
  }
  return done ?? false;
}

class _ContactForm extends ConsumerStatefulWidget {
  const _ContactForm({this.studentId, this.contactId, this.initial});

  final int? studentId;
  final int? contactId;
  final ContactRow? initial;

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  late final ContactRow? _i = widget.initial;
  late final TextEditingController _first = TextEditingController(
    text: _i?.firstName,
  );
  late final TextEditingController _last = TextEditingController(
    text: _i?.lastName,
  );
  late final TextEditingController _phone = TextEditingController(
    text: _i?.phone,
  );
  late final TextEditingController _email = TextEditingController(
    text: _i?.email,
  );
  late final TextEditingController _relationship = TextEditingController(
    text: _i?.relationship,
  );
  late final TextEditingController _occupation = TextEditingController(
    text: _i?.occupation,
  );
  late final TextEditingController _address = TextEditingController(
    text: _i?.address,
  );
  late bool _primary = _i?.isPrimary ?? false;
  late bool _deceased = _i?.aliveStatus == 'deceased';
  bool _busy = false;

  bool get _editing => widget.contactId != null;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _first,
      _last,
      _phone,
      _email,
      _relationship,
      _occupation,
      _address,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  ContactInput get _input => ContactInput(
    phone: _phone.text.trim(),
    firstName: _first.text.trim(),
    lastName: _last.text.trim(),
    email: _email.text.trim(),
    address: _address.text.trim(),
    occupation: _occupation.text.trim(),
    relationship: _relationship.text.trim(),
    isPrimary: _primary,
    aliveStatus: _deceased ? 'deceased' : 'alive',
  );

  Future<void> _save() async {
    if (_phone.text.trim().isEmpty) {
      _snack(context, 'Phone number is required');
      return;
    }
    setState(() => _busy = true);
    final Result<Object?> r = _editing
        ? await ref
              .read(studentAdminRepositoryProvider)
              .updateContact(widget.contactId!, _input)
        : await ref
              .read(studentAdminRepositoryProvider)
              .addContact(widget.studentId!, _input);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Ok<Object?>(:final Object? value):
        _snack(context, value is String ? value : 'Contact updated successfully');
        Navigator.of(context).pop(true);
      case Err<Object?>(:final Failure failure):
        _snack(context, failure.message);
    }
  }

  Future<void> _remove() async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove this contact?'),
        content: const Text(
          'The contact is removed from every learner it is linked to.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    final Result<void> r = await ref
        .read(studentAdminRepositoryProvider)
        .removeContact(widget.contactId!);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r is Ok<void>) {
      _snack(context, 'Contact deleted successfully');
      Navigator.of(context).pop(true);
    } else if (r case Err<void>(:final Failure failure)) {
      _snack(context, failure.message);
    }
  }

  Widget _f(TextEditingController c, String label, {TextInputType? kb}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: kb,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _editing ? 'Edit contact' : 'Add contact',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _f(_phone, 'Phone *', kb: TextInputType.phone),
            _f(_first, 'First name'),
            _f(_last, 'Last name'),
            _f(_relationship, 'Relationship (e.g. Mother)'),
            _f(_email, 'Email', kb: TextInputType.emailAddress),
            _f(_occupation, 'Occupation'),
            _f(_address, 'Address'),
            if (!_editing)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Primary contact'),
                value: _primary,
                onChanged: (bool v) => setState(() => _primary = v),
              )
            else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Deceased'),
                value: _deceased,
                onChanged: (bool v) => setState(() => _deceased = v),
              ),
            if (!_editing)
              Text(
                'A contact already on file with this phone or email is linked '
                'rather than duplicated.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                if (_editing)
                  TextButton(
                    onPressed: _busy ? null : _remove,
                    child: const Text('Remove'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Contacts — the web /students/contacts
// ─────────────────────────────────────────────────────────────────────────

/// Every learner's contacts, searchable — the web `/students/contacts`.
class ContactsPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const ContactsPage({super.key});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  String? _search;
  int _limit = 50;

  @override
  Widget build(BuildContext context) {
    final ({String? search, int limit}) key = (search: _search, limit: _limit);
    final AsyncValue<ContactPage> page = ref.watch(contactsProvider(key));

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Contacts',
        subtitle: page.maybeWhen(
          data: (ContactPage p) => '${p.total} contacts',
          orElse: () => null,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search learner, contact or relationship',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (String v) => setState(() {
                _search = v.trim().isEmpty ? null : v.trim();
                _limit = 50;
              }),
            ),
          ),
        ),
      ),
      body: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => ErrorView(
          title: 'Could not load contacts',
          message: _messageOf(e),
          onRetry: () => ref.invalidate(contactsProvider(key)),
        ),
        data: (ContactPage p) => p.rows.isEmpty
            ? const Center(child: Text('No contacts match'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: p.rows.length + (p.hasMore ? 1 : 0),
                itemBuilder: (BuildContext context, int i) {
                  if (i == p.rows.length) {
                    // The route caps a page at 200; asking for more rows of
                    // page 1 keeps the list in one ordered piece.
                    return TextButton(
                      onPressed: _limit >= 200
                          ? null
                          : () => setState(() => _limit += 50),
                      child: Text(
                        _limit >= 200
                            ? 'Showing the first 200 — search to narrow'
                            : 'Show more',
                      ),
                    );
                  }
                  final ContactRow c = p.rows[i];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        c.isPrimary ? Icons.star : Icons.person_outline,
                        color: c.isPrimary
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(c.contactLabel),
                      subtitle: Text(
                        <String?>[
                          c.relationship,
                          c.phone,
                          'for ${c.studentLabel}',
                          c.className,
                        ].whereType<String>().join(' · '),
                      ),
                      onTap: () => showContactSheet(
                        context,
                        ref,
                        contactId: c.contactId,
                        initial: c,
                      ),
                      onLongPress: () => context.push(
                        AppRoutes.studentDetailPath(c.studentId),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Duplicates — the web /students/duplicates
// ─────────────────────────────────────────────────────────────────────────

/// Possible duplicate learners, and merging them.
class DuplicatesPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const DuplicatesPage({super.key});

  @override
  ConsumerState<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends ConsumerState<DuplicatesPage> {
  /// Chosen record to keep, per group. Defaults to the oldest.
  final Map<int, int> _keep = <int, int>{};
  int? _merging;

  Future<void> _merge(DuplicateGroup g) async {
    final int keep = _keep[g.groupId] ?? g.students.first.id;
    final List<DuplicateMember> others = g.students
        .where((DuplicateMember s) => s.id != keep)
        .toList();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Merge ${others.length} into #$keep?'),
        content: const Text(
          'Enrolments, results, fee records and promotions move to the kept '
          'record, and the others go to Trash.\n\n'
          'As on the web app, the duplicates\' fingerprint attendance, '
          'device enrolments and contacts are NOT moved — check them before '
          'merging a record that has been clocking in.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _merging = g.groupId);
    final Result<List<MergeOutcome>> r = await ref
        .read(studentAdminRepositoryProvider)
        .merge(<({int primaryId, List<int> secondaryIds})>[
          (
            primaryId: keep,
            secondaryIds: others.map((DuplicateMember s) => s.id).toList(),
          ),
        ]);
    if (!mounted) return;
    setState(() => _merging = null);
    final String message = switch (r) {
      Ok<List<MergeOutcome>>(:final List<MergeOutcome> value) =>
        value.first.success
            ? 'Merged ${others.length} duplicate(s)'
            : (value.first.error ?? 'Merge failed'),
      Err<List<MergeOutcome>>(:final Failure failure) => failure.message,
    };
    ref
      ..invalidate(duplicatesProvider)
      ..invalidate(studentListProvider);
    _snack(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<DuplicateReport> report = ref.watch(duplicatesProvider);

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Duplicates',
        subtitle: report.maybeWhen(
          data: (DuplicateReport r) =>
              '${r.groups.length} groups · ${r.totalStudents} learners checked',
          orElse: () => null,
        ),
      ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => ErrorView(
          title: 'Could not check for duplicates',
          message: _messageOf(e),
          onRetry: () => ref.invalidate(duplicatesProvider),
        ),
        data: (DuplicateReport r) => r.groups.isEmpty
            ? const Center(child: Text('No duplicates found'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  for (final DuplicateGroup g in r.groups)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    g.matchReason,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                DraisPill(
                                  label: g.confidence,
                                  color: g.confidence == 'high'
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.tertiary,
                                ),
                              ],
                            ),
                            for (final DuplicateMember s in g.students)
                              RadioListTile<int>(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: s.id,
                                // ignore: deprecated_member_use
                                groupValue: _keep[g.groupId] ?? g.students.first.id,
                                // ignore: deprecated_member_use
                                onChanged: (int? v) => setState(
                                  () => _keep[g.groupId] = v ?? s.id,
                                ),
                                title: Text('${s.name} · #${s.id}'),
                                subtitle: Text(
                                  <String?>[
                                    s.admissionNo,
                                    s.className,
                                    '${s.enrollmentCount} enrolments',
                                    '${s.resultsCount} results',
                                    s.createdAt?.split(' ').first,
                                  ].whereType<String>().join(' · '),
                                ),
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _merging == g.groupId
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: _merging == null
                                          ? () => _merge(g)
                                          : null,
                                      child: const Text('Merge, keep selected'),
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

// ─────────────────────────────────────────────────────────────────────────
// Promote a class — the web enrol page's "bulk promote"
// ─────────────────────────────────────────────────────────────────────────

/// Moves every learner actively enrolled in one class to another.
class PromoteClassPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const PromoteClassPage({super.key});

  @override
  ConsumerState<PromoteClassPage> createState() => _PromoteClassPageState();
}

class _PromoteClassPageState extends ConsumerState<PromoteClassPage> {
  int? _from;
  int? _to;
  int? _year;
  int? _term;
  bool _seeded = false;
  bool _busy = false;

  void _seed(EnrollmentOptions o) {
    if (_seeded) return;
    _seeded = true;
    _term = o.currentTerm?.id;
    _year = o.currentTerm?.academicYearId;
  }

  Future<void> _submit(EnrollmentOptions o) async {
    if (_from == null || _to == null || _year == null) {
      _snack(context, 'From class, to class and academic year are required');
      return;
    }
    final String from = o.classes.firstWhere((Choice c) => c.id == _from).label;
    final String to = o.classes.firstWhere((Choice c) => c.id == _to).label;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Promote $from to $to?'),
        content: const Text(
          'Every learner actively enrolled in the first class has that '
          'enrolment completed and a new one opened in the second.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Promote'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _busy = true);
    final Result<int> r = await ref
        .read(studentAdminRepositoryProvider)
        .promoteClass(
          fromClassId: _from!,
          toClassId: _to!,
          academicYearId: _year!,
          termId: _term,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Ok<int>(:final int value):
        ref.invalidate(studentListProvider);
        _snack(
          context,
          value == 0 ? 'No students found in class' : 'Promoted $value learners',
        );
        if (value > 0) context.pop();
      case Err<int>(:final Failure failure):
        _snack(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<EnrollmentOptions> options = ref.watch(
      enrollmentOptionsProvider,
    );
    return Scaffold(
      appBar: const DraisAppBar(title: 'Promote a class'),
      body: options.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => ErrorView(
          title: 'Could not load classes',
          message: _messageOf(e),
          onRetry: () => ref.invalidate(enrollmentOptionsProvider),
        ),
        data: (EnrollmentOptions o) {
          _seed(o);
          final List<Choice> terms = <Choice>[
            for (final TermChoice t in o.terms)
              if (_year == null || t.academicYearId == _year)
                Choice(id: t.id, label: t.name),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: <Widget>[
              ChoicePicker(
                label: 'From class',
                value: _from,
                items: o.classes,
                onChanged: (int? v) => setState(() => _from = v),
              ),
              ChoicePicker(
                label: 'To class',
                value: _to,
                items: o.classes,
                onChanged: (int? v) => setState(() => _to = v),
              ),
              ChoicePicker(
                label: 'Academic year',
                value: _year,
                items: o.academicYears,
                onChanged: (int? v) => setState(() => _year = v),
              ),
              ChoicePicker(
                label: 'Term',
                value: _term,
                items: terms,
                required: false,
                onChanged: (int? v) => setState(() => _term = v),
              ),
              Text(
                'With no term chosen, the school\'s current term is used.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.trending_up),
                label: Text(_busy ? 'Promoting…' : 'Promote'),
                onPressed: _busy ? null : () => _submit(o),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Bulk enrol — the web /students/enroll-bulk
// ─────────────────────────────────────────────────────────────────────────

/// Enrols several admitted learners into the same class, term and program.
class BulkEnrollPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const BulkEnrollPage({super.key});

  @override
  ConsumerState<BulkEnrollPage> createState() => _BulkEnrollPageState();
}

class _BulkEnrollPageState extends ConsumerState<BulkEnrollPage> {
  final Set<int> _picked = <int>{};
  bool _seeded = false;
  int? _class;
  int? _stream;
  int? _year;
  int? _term;
  int? _mode;
  int? _curriculum;
  int? _program;
  EnrollmentDecision _decision = EnrollmentDecision.firstTime;
  bool _busy = false;

  void _seed(EnrollmentOptions o) {
    if (_seeded) return;
    _seeded = true;
    _term = o.currentTerm?.id;
    _year = o.currentTerm?.academicYearId;
    _mode = o.studyModes.where((Choice c) => c.isDefault).firstOrNull?.id;
  }

  Future<void> _submit() async {
    if (_picked.isEmpty) {
      _snack(context, 'Choose at least one learner');
      return;
    }
    if (<int?>[_class, _year, _term, _mode, _curriculum, _program].contains(null)) {
      _snack(
        context,
        'All of class, academic year, term, study mode, curriculum and program are required',
      );
      return;
    }
    setState(() => _busy = true);
    final Result<BulkEnrollResult> r = await ref
        .read(studentAdminRepositoryProvider)
        .enrollMany(
          studentIds: _picked.toList(),
          classId: _class!,
          streamId: _stream,
          academicYearId: _year!,
          termId: _term!,
          studyModeId: _mode!,
          curriculumId: _curriculum!,
          programId: _program!,
          decision: _decision,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Ok<BulkEnrollResult>(:final BulkEnrollResult value):
        ref.invalidate(studentListProvider);
        _snack(context, value.message);
        if (value.successful > 0) context.pop();
      case Err<BulkEnrollResult>(:final Failure failure):
        _snack(context, failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<EnrollmentOptions> options = ref.watch(
      enrollmentOptionsProvider,
    );
    final AsyncValue<StudentListResult> admitted = ref.watch(
      studentListProvider((
        tab: StudentsTab.admitted,
        search: null,
        classId: null,
      )),
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Bulk enrol',
        subtitle: '${_picked.length} selected',
      ),
      body: switch ((options, admitted)) {
        (
          AsyncData<EnrollmentOptions>(:final EnrollmentOptions value),
          AsyncData<StudentListResult>(value: final StudentListResult list),
        ) =>
          () {
            _seed(value);
            final EnrollmentOptions o = value;
            final List<Choice> streams = o.streams
                .where((Choice s) => _class == null || s.parentId == _class)
                .toList();
            final List<Choice> terms = <Choice>[
              for (final TermChoice t in o.terms)
                if (_year == null || t.academicYearId == _year)
                  Choice(id: t.id, label: t.name),
            ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: <Widget>[
                Text('Learners not enrolled this term', style: theme.textTheme.titleSmall),
                Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: () => setState(
                        () => _picked.addAll(
                          list.rows.map((StudentListRow s) => s.id),
                        ),
                      ),
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed: () => setState(_picked.clear),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                if (list.rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('Everyone admitted is enrolled this term.'),
                  ),
                for (final StudentListRow s in list.rows)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _picked.contains(s.id),
                    onChanged: (bool? v) => setState(
                      () => (v ?? false) ? _picked.add(s.id) : _picked.remove(s.id),
                    ),
                    title: Text(s.displayName),
                    subtitle: Text(s.admissionNo ?? 'No admission number'),
                  ),
                const Divider(height: 32),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final EnrollmentDecision d in EnrollmentDecision.values)
                      ChoiceChip(
                        label: Text(d.label),
                        selected: _decision == d,
                        onSelected: (_) => setState(() => _decision = d),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ChoicePicker(
                  label: 'Class',
                  value: _class,
                  items: o.classes,
                  onChanged: (int? v) => setState(() {
                    _class = v;
                    _stream = null;
                  }),
                ),
                ChoicePicker(
                  label: 'Stream',
                  value: _stream,
                  items: streams,
                  required: false,
                  onChanged: (int? v) => setState(() => _stream = v),
                ),
                ChoicePicker(
                  label: 'Academic year',
                  value: _year,
                  items: o.academicYears,
                  onChanged: (int? v) => setState(() => _year = v),
                ),
                ChoicePicker(
                  label: 'Term',
                  value: _term,
                  items: terms,
                  onChanged: (int? v) => setState(() => _term = v),
                ),
                ChoicePicker(
                  label: 'Study mode',
                  value: _mode,
                  items: o.studyModes,
                  onChanged: (int? v) => setState(() => _mode = v),
                ),
                ChoicePicker(
                  label: 'Curriculum',
                  value: _curriculum,
                  items: o.curriculums,
                  onChanged: (int? v) => setState(() => _curriculum = v),
                ),
                ChoicePicker(
                  label: 'Program',
                  value: _program,
                  items: o.programs,
                  onChanged: (int? v) => setState(() => _program = v),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.how_to_reg),
                  label: Text(
                    _busy ? 'Enrolling…' : 'Enrol ${_picked.length} learners',
                  ),
                  onPressed: _busy ? null : _submit,
                ),
              ],
            );
          }(),
        (AsyncError<EnrollmentOptions>(:final Object error), _) ||
        (_, AsyncError<StudentListResult>(:final Object error)) => ErrorView(
          title: 'Could not load the form',
          message: _messageOf(error),
          onRetry: () => ref
            ..invalidate(enrollmentOptionsProvider)
            ..invalidate(studentListProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
