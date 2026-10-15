import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/application/students_providers.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';

/// Admit a learner — the mobile counterpart of the web `/students/admit`.
///
/// Step 1 of 2, as on the web: admission creates the student record only;
/// class and term come from the enrol form, which this screen offers next.
class AdmitStudentPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const AdmitStudentPage({super.key});

  @override
  ConsumerState<AdmitStudentPage> createState() => _AdmitStudentPageState();
}

class _AdmitStudentPageState extends ConsumerState<AdmitStudentPage> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _first = TextEditingController();
  final TextEditingController _last = TextEditingController();
  final TextEditingController _other = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  String _gender = 'female';
  DateTime? _dob;
  bool _saving = false;
  String? _error;
  ({int id, String name})? _admitted;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _other.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final Result<AdmissionResult> result = await ref
        .read(studentsRepositoryProvider)
        .admit(
          AdmissionRequest(
            firstName: _first.text,
            lastName: _last.text,
            otherName: _other.text,
            gender: _gender,
            dateOfBirth: _dob == null ? null : toLocalDateStr(_dob),
            phone: _phone.text,
          ),
        );

    if (!mounted) return;
    switch (result) {
      case Ok<AdmissionResult>(:final AdmissionResult value):
        ref.invalidate(studentListProvider);
        setState(() {
          _saving = false;
          _admitted = (
            id: value.studentId,
            name: '${_first.text.trim()} ${_last.text.trim()}',
          );
        });
      case Err<AdmissionResult>(:final Failure failure):
        setState(() {
          _saving = false;
          _error = failure.message;
        });
    }
  }

  void _another() {
    _first.clear();
    _last.clear();
    _other.clear();
    _phone.clear();
    setState(() {
      _gender = 'female';
      _dob = null;
      _admitted = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DraisAppBar(
        title: 'Admit student',
        subtitle: 'Step 1 of 2 — create the student record',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: <Widget>[
          if (_admitted != null) _success(context) else _formCard(context),
        ],
      ),
    );
  }

  Widget _success(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ({int id, String name}) a = _admitted!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Student admitted', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            // The route returns no admission number; the web shows `#id`.
            Text('${a.name} — #${a.id}', textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'Now enrol this learner into a class and term.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Enrol now'),
              onPressed: () =>
                  context.pushReplacement(AppRoutes.enrollStudentPath(a.id)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _another, child: const Text('Admit another')),
            TextButton(
              onPressed: () => context.go(AppRoutes.students),
              child: const Text('View students'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Required' : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Admission creates a student record only. You can enrol them '
                'into a class and term straight after.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _first,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'First name *',
                  border: OutlineInputBorder(),
                ),
                validator: required,
              ),
              const SizedBox(height: 12),
              // The web form marks this optional, but the platform's route
              // rejects an admission without it; asking up front is kinder
              // than failing after submit. See docs/PARITY.md §4.2.
              TextFormField(
                controller: _last,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Last name *',
                  border: OutlineInputBorder(),
                ),
                validator: required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _other,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Other name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'female', child: Text('Female')),
                  DropdownMenuItem<String>(value: 'male', child: Text('Male')),
                  DropdownMenuItem<String>(value: 'other', child: Text('Other')),
                  DropdownMenuItem<String>(
                    value: 'not_specified',
                    child: Text('Prefer not to say'),
                  ),
                ],
                onChanged: (String? v) => setState(() => _gender = v ?? 'female'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.cake_outlined),
                label: Text(
                  _dob == null
                      ? 'Date of birth'
                      : 'Born ${toLocalDateStr(_dob)}',
                ),
                onPressed: () async {
                  final DateTime now = DateTime.now();
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _dob ?? DateTime(now.year - 8),
                    firstDate: DateTime(now.year - 40),
                    lastDate: now,
                  );
                  if (picked != null) setState(() => _dob = picked);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  hintText: 'e.g. 0700 000 000',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1),
                label: Text(_saving ? 'Admitting…' : 'Admit student'),
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
