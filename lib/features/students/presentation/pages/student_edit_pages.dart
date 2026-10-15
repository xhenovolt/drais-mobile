import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/application/students_providers.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// Loads a learner's profile and hands it to [builder] once it is ready.
class _ProfileLoader extends ConsumerWidget {
  const _ProfileLoader({
    required this.studentId,
    required this.title,
    required this.builder,
  });

  final int studentId;
  final String title;
  final Widget Function(StudentProfile profile) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StudentProfile> p = ref.watch(
      studentProfileProvider(studentId),
    );
    return p.when(
      data: builder,
      loading: () => Scaffold(
        appBar: DraisAppBar(title: title),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object e, StackTrace _) => Scaffold(
        appBar: DraisAppBar(title: title),
        body: ErrorView(
          title: 'Could not load this learner',
          message: e is Failure ? e.message : 'Something went wrong.',
          onRetry: () => ref.invalidate(studentProfileProvider(studentId)),
        ),
      ),
    );
  }
}

/// Runs a save, reports the outcome, and returns to the learner on success.
Future<void> _save(
  BuildContext context,
  WidgetRef ref,
  int studentId,
  Future<Result<Object?>> Function() run, {
  required String success,
  required void Function(bool) busy,
}) async {
  busy(true);
  final Result<Object?> result = await run();
  if (!context.mounted) return;
  busy(false);
  switch (result) {
    case Ok<Object?>():
      ref
        ..invalidate(studentProfileProvider(studentId))
        ..invalidate(studentListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      context.pop();
    case Err<Object?>(:final Failure failure):
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

Widget _field(
  TextEditingController c,
  String label, {
  TextInputType? keyboard,
  int maxLines = 1,
  String? Function(String?)? validator,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextFormField(
    controller: c,
    keyboardType: keyboard,
    maxLines: maxLines,
    validator: validator,
    textCapitalization: keyboard == null
        ? TextCapitalization.sentences
        : TextCapitalization.none,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  ),
);

String? _orNull(TextEditingController c) =>
    c.text.trim().isEmpty ? null : c.text.trim();

// ─────────────────────────────────────────────────────────────────────────
// Personal details — PUT /api/students/edit
// ─────────────────────────────────────────────────────────────────────────

/// Edit a learner's personal details — the web list page's edit form.
///
/// Every field is sent, as the web form does; the route records in the audit
/// log only the ones whose value actually changed.
class EditStudentPage extends ConsumerWidget {
  /// Creates the page.
  const EditStudentPage({required this.studentId, super.key});

  /// `students.id`.
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ProfileLoader(
    studentId: studentId,
    title: 'Edit details',
    builder: (StudentProfile p) => _EditStudentForm(profile: p),
  );
}

class _EditStudentForm extends ConsumerStatefulWidget {
  const _EditStudentForm({required this.profile});

  final StudentProfile profile;

  @override
  ConsumerState<_EditStudentForm> createState() => _EditStudentFormState();
}

class _EditStudentFormState extends ConsumerState<_EditStudentForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final StudentListRow _r = widget.profile.row;
  late final TextEditingController _first = TextEditingController(
    text: _r.firstName,
  );
  late final TextEditingController _last = TextEditingController(
    text: _r.lastName,
  );
  late final TextEditingController _other = TextEditingController(
    text: _r.otherName,
  );
  late final TextEditingController _phone = TextEditingController(
    text: _r.phone,
  );
  late final TextEditingController _email = TextEditingController(
    text: _r.email,
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.profile.address,
  );
  late String? _gender = _r.gender;
  late String? _dob = _r.dateOfBirth?.split(' ').first;
  bool _busy = false;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _first,
      _last,
      _other,
      _phone,
      _email,
      _address,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Required' : null;
    const List<String> genders = <String>[
      'female',
      'male',
      'other',
      'not_specified',
    ];
    // A stored value outside the list (e.g. 'M') is kept selectable rather
    // than silently replaced.
    final List<String> options = <String>[
      ...genders,
      if (_gender != null && !genders.contains(_gender)) _gender!,
    ];

    return Scaffold(
      appBar: DraisAppBar(title: 'Edit details', subtitle: _r.displayName),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: <Widget>[
            _field(_first, 'First name *', validator: required),
            _field(_last, 'Last name *', validator: required),
            _field(_other, 'Other name'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String?>(
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(child: Text('Not recorded')),
                  for (final String g in options)
                    DropdownMenuItem<String?>(
                      value: g,
                      child: Text(g.replaceAll('_', ' ')),
                    ),
                ],
                onChanged: (String? v) => setState(() => _gender = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.cake_outlined),
                label: Text(_dob == null ? 'Date of birth' : 'Born $_dob'),
                onPressed: () async {
                  final DateTime now = DateTime.now();
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate:
                        parseLocalDate(_dob) ?? DateTime(now.year - 8),
                    firstDate: DateTime(now.year - 60),
                    lastDate: now,
                  );
                  if (picked != null) {
                    setState(() => _dob = toLocalDateStr(picked));
                  }
                },
              ),
            ),
            _field(_phone, 'Phone', keyboard: TextInputType.phone),
            _field(_email, 'Email', keyboard: TextInputType.emailAddress),
            _field(_address, 'Address', maxLines: 2),
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Saving…' : 'Save'),
              onPressed: _busy
                  ? null
                  : () {
                      if (!(_form.currentState?.validate() ?? false)) return;
                      _save(
                        context,
                        ref,
                        _r.id,
                        () => ref
                            .read(studentsRepositoryProvider)
                            .update(
                              _r.id,
                              StudentEdit(
                                firstName: _first.text.trim(),
                                lastName: _last.text.trim(),
                                otherName: _other.text.trim(),
                                gender: _gender,
                                dateOfBirth: _dob,
                                phone: _phone.text.trim(),
                                email: _email.text.trim(),
                                address: _address.text.trim(),
                              ),
                            ),
                        success: 'Student updated successfully',
                        busy: (bool b) => setState(() => _busy = b),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Family and background — PUT /api/students/[id]/profile
// ─────────────────────────────────────────────────────────────────────────

/// Edit family and background — the three profile blocks.
class EditStudentProfilePage extends ConsumerWidget {
  /// Creates the page.
  const EditStudentProfilePage({required this.studentId, super.key});

  /// `students.id`.
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ProfileLoader(
    studentId: studentId,
    title: 'Family & background',
    builder: (StudentProfile p) => _ProfileBlocksForm(profile: p),
  );
}

class _ProfileBlocksForm extends ConsumerStatefulWidget {
  const _ProfileBlocksForm({required this.profile});

  final StudentProfile profile;

  @override
  ConsumerState<_ProfileBlocksForm> createState() => _ProfileBlocksFormState();
}

class _ProfileBlocksFormState extends ConsumerState<_ProfileBlocksForm> {
  late final ProfileBlocks _b = widget.profile.blocks;
  late final TextEditingController _guardian = TextEditingController(
    text: _b.guardianName,
  );
  late final TextEditingController _guardianContact = TextEditingController(
    text: _b.guardianContact,
  );
  late final TextEditingController _guardianJob = TextEditingController(
    text: _b.guardianOccupation,
  );
  late final TextEditingController _father = TextEditingController(
    text: _b.fatherName,
  );
  late final TextEditingController _fatherContact = TextEditingController(
    text: _b.fatherContact,
  );
  late final TextEditingController _fatherJob = TextEditingController(
    text: _b.fatherOccupation,
  );
  late final TextEditingController _birth = TextEditingController(
    text: _b.placeOfBirth,
  );
  late final TextEditingController _residence = TextEditingController(
    text: _b.placeOfResidence,
  );
  late final TextEditingController _prevSchool = TextEditingController(
    text: _b.previousSchool,
  );
  late final TextEditingController _notes = TextEditingController(
    text: _b.notes,
  );
  bool _busy = false;

  List<TextEditingController> get _all => <TextEditingController>[
    _guardian,
    _guardianContact,
    _guardianJob,
    _father,
    _fatherContact,
    _fatherJob,
    _birth,
    _residence,
    _prevSchool,
    _notes,
  ];

  @override
  void dispose() {
    for (final TextEditingController c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int id = widget.profile.row.id;

    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(t, style: theme.textTheme.titleSmall),
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Family & background',
        subtitle: widget.profile.row.displayName,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: <Widget>[
          heading('Guardian'),
          _field(_guardian, 'Guardian name'),
          _field(_guardianContact, 'Guardian contact', keyboard: TextInputType.phone),
          _field(_guardianJob, 'Guardian occupation'),
          heading('Father'),
          _field(_father, 'Father name'),
          _field(_fatherContact, 'Father contact', keyboard: TextInputType.phone),
          _field(_fatherJob, 'Father occupation'),
          heading('Background'),
          _field(_birth, 'Place of birth'),
          _field(_residence, 'Place of residence'),
          _field(_prevSchool, 'Previous school'),
          _field(_notes, 'Notes', maxLines: 3),
          Text(
            // District, nationality, orphan and living status are chosen from
            // lists on the web; their stored values are kept unchanged here.
            'District, nationality and orphan status are kept as recorded.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined),
            label: Text(_busy ? 'Saving…' : 'Save'),
            onPressed: _busy
                ? null
                : () => _save(
                    context,
                    ref,
                    id,
                    () => ref
                        .read(studentsRepositoryProvider)
                        .saveProfileBlocks(
                          id,
                          _b.withText(
                            previousSchool: _orNull(_prevSchool),
                            notes: _orNull(_notes),
                            placeOfBirth: _orNull(_birth),
                            placeOfResidence: _orNull(_residence),
                            guardianName: _orNull(_guardian),
                            guardianContact: _orNull(_guardianContact),
                            guardianOccupation: _orNull(_guardianJob),
                            fatherName: _orNull(_father),
                            fatherOccupation: _orNull(_fatherJob),
                            fatherContact: _orNull(_fatherContact),
                          ),
                        ),
                    success: 'Profile saved',
                    busy: (bool b) => setState(() => _busy = b),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Next of kin — POST /api/students/[id]/next-of-kin
// ─────────────────────────────────────────────────────────────────────────

/// Edit next of kin. Saving replaces the whole list, as the route does.
class NextOfKinPage extends ConsumerWidget {
  /// Creates the page.
  const NextOfKinPage({required this.studentId, super.key});

  /// `students.id`.
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ProfileLoader(
    studentId: studentId,
    title: 'Next of kin',
    builder: (StudentProfile p) => _NextOfKinForm(profile: p),
  );
}

class _KinRow {
  _KinRow(NextOfKinEntry? e)
    : name = TextEditingController(text: e?.name),
      contact = TextEditingController(text: e?.contact),
      occupation = TextEditingController(text: e?.occupation),
      address = TextEditingController(text: e?.address);

  final TextEditingController name;
  final TextEditingController contact;
  final TextEditingController occupation;
  final TextEditingController address;

  void dispose() {
    name.dispose();
    contact.dispose();
    occupation.dispose();
    address.dispose();
  }
}

class _NextOfKinForm extends ConsumerStatefulWidget {
  const _NextOfKinForm({required this.profile});

  final StudentProfile profile;

  @override
  ConsumerState<_NextOfKinForm> createState() => _NextOfKinFormState();
}

class _NextOfKinFormState extends ConsumerState<_NextOfKinForm> {
  late final List<_KinRow> _rows = <_KinRow>[
    for (final NextOfKinEntry e in widget.profile.nextOfKinEntries) _KinRow(e),
    if (widget.profile.nextOfKinEntries.isEmpty) _KinRow(null),
  ];
  bool _busy = false;

  @override
  void dispose() {
    for (final _KinRow r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int id = widget.profile.row.id;

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Next of kin',
        subtitle: widget.profile.row.displayName,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: <Widget>[
          for (int i = 0; i < _rows.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          _field(_rows[i].name, 'Name'),
                          _field(
                            _rows[i].contact,
                            'Contact',
                            keyboard: TextInputType.phone,
                          ),
                          _field(_rows[i].occupation, 'Occupation'),
                          _field(_rows[i].address, 'Address'),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => setState(() {
                        _rows.removeAt(i).dispose();
                      }),
                    ),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add next of kin'),
            onPressed: () => setState(() => _rows.add(_KinRow(null))),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined),
            label: Text(_busy ? 'Saving…' : 'Save'),
            onPressed: _busy
                ? null
                : () => _save(
                    context,
                    ref,
                    id,
                    () => ref
                        .read(studentsRepositoryProvider)
                        .saveNextOfKin(id, <NextOfKinEntry>[
                          // Sequence follows the order on screen; the route
                          // numbers rows that arrive without one.
                          for (final _KinRow r in _rows)
                            NextOfKinEntry(
                              name: r.name.text,
                              contact: _orNull(r.contact),
                              occupation: _orNull(r.occupation),
                              address: _orNull(r.address),
                            ),
                        ]),
                    success: 'Next of kin saved',
                    busy: (bool b) => setState(() => _busy = b),
                  ),
          ),
        ],
      ),
    );
  }
}
