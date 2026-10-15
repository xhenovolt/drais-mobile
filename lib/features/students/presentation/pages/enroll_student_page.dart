import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/students/application/enrollment_suggestions.dart';
import 'package:drais/features/students/application/students_providers.dart';
import 'package:drais/features/students/domain/entities/students.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// Enrol one learner — the mobile counterpart of the web `/students/enroll`
/// single-learner flow, posting to the same `POST /api/enrollments`.
///
/// Pre-selection follows the web form exactly: the date-current term and its
/// academic year; the previous enrolment's study mode, curriculum, program
/// and class; the school's default study mode when nothing else applies; and
/// the class moved one level up or down for promote or demote.
class EnrollStudentPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const EnrollStudentPage({required this.studentId, super.key});

  /// `students.id`.
  final int studentId;

  @override
  ConsumerState<EnrollStudentPage> createState() => _EnrollStudentPageState();
}

class _EnrollStudentPageState extends ConsumerState<EnrollStudentPage> {
  bool _seeded = false;
  EnrollmentDecision? _decision;
  int? _classId;
  int? _streamId;
  int? _yearId;
  int? _termId;
  int? _modeId;
  int? _curriculumId;
  int? _programId;
  bool _saving = false;
  String? _error;

  /// Applies the web form's defaults once, when both loads have arrived.
  void _seed(EnrollmentOptions o, EnrollmentRecord? prev) {
    if (_seeded) return;
    _seeded = true;
    _termId = o.currentTerm?.id;
    _yearId = o.currentTerm?.academicYearId;
    _decision = prev == null
        ? EnrollmentDecision.firstTime
        : EnrollmentDecision.continueSame;
    _modeId =
        prev?.studyModeId ??
        o.studyModes.where((Choice c) => c.isDefault).firstOrNull?.id;
    _curriculumId = prev?.curriculumId;
    _programId = prev?.programId;
    _classId = prev?.classId;
  }

  Future<void> _submit(EnrollmentOptions o) async {
    // The web form's checks, in its order and with its messages.
    String? problem;
    if (_classId == null || _termId == null || _yearId == null || _decision == null) {
      problem = 'Please complete all required fields';
    } else if (_modeId == null) {
      problem = 'Study mode is required — select one before enrolling';
    } else if (_curriculumId == null) {
      problem = 'Curriculum is required — select one before enrolling';
    } else if (_programId == null) {
      problem = 'Program is required — select one before enrolling';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final Result<String> result = await ref
        .read(studentsRepositoryProvider)
        .enroll(
          EnrollmentRequest(
            studentId: widget.studentId,
            classId: _classId!,
            streamId: _streamId,
            academicYearId: _yearId!,
            termId: _termId!,
            studyModeId: _modeId!,
            curriculumId: _curriculumId!,
            programId: _programId!,
            decision: _decision!,
          ),
        );
    if (!mounted) return;

    switch (result) {
      case Ok<String>(:final String value):
        ref
          ..invalidate(studentListProvider)
          ..invalidate(studentProfileProvider(widget.studentId))
          ..invalidate(previousEnrollmentProvider(widget.studentId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
        context.pop();
      case Err<String>(:final Failure failure):
        setState(() {
          _saving = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<EnrollmentOptions> options = ref.watch(
      enrollmentOptionsProvider,
    );
    final AsyncValue<EnrollmentRecord?> previous = ref.watch(
      previousEnrollmentProvider(widget.studentId),
    );
    final AsyncValue<StudentProfile> profile = ref.watch(
      studentProfileProvider(widget.studentId),
    );

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Enrol',
        subtitle: profile.valueOrNull?.row.displayName,
      ),
      body: switch ((options, previous)) {
        (AsyncData<EnrollmentOptions>(:final EnrollmentOptions value),
            AsyncData<EnrollmentRecord?>(value: final EnrollmentRecord? prev)) =>
          _form(context, value, prev),
        (AsyncError<EnrollmentOptions>(:final Object error), _) ||
        (_, AsyncError<EnrollmentRecord?>(:final Object error)) => ErrorView(
          title: 'Could not load the enrolment form',
          message: error is Failure ? error.message : 'Something went wrong.',
          onRetry: () {
            ref
              ..invalidate(enrollmentOptionsProvider)
              ..invalidate(previousEnrollmentProvider(widget.studentId));
          },
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _form(BuildContext context, EnrollmentOptions o, EnrollmentRecord? prev) {
    _seed(o, prev);
    final ThemeData theme = Theme.of(context);
    final List<TermChoice> terms = _yearId == null
        ? o.terms
        : o.terms.where((TermChoice t) => t.academicYearId == _yearId).toList();
    final List<Choice> streams = _classId == null
        ? o.streams
        : o.streams.where((Choice s) => s.parentId == _classId).toList();

    Widget picker(
      String label,
      int? value,
      List<Choice> items,
      ValueChanged<int?> onChanged, {
      bool required = true,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        key: ValueKey<String>('$label-$value-${items.length}'),
        initialValue: items.any((Choice c) => c.id == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<int?>>[
          if (!required) const DropdownMenuItem<int?>(child: Text('None')),
          for (final Choice c in items)
            DropdownMenuItem<int?>(value: c.id, child: Text(c.label)),
        ],
        onChanged: onChanged,
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: <Widget>[
        if (prev != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                'Previously ${prev.className ?? 'unknown class'}'
                '${prev.termName == null ? '' : ' · ${prev.termName}'}',
              ),
              subtitle: Text(
                <String?>[prev.academicYearName, prev.programName, prev.status]
                    .whereType<String>()
                    .join(' · '),
              ),
            ),
          ),
        if (o.currentTerm == null)
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: const ListTile(
              leading: Icon(Icons.event_busy),
              title: Text('No term covers today'),
              subtitle: Text(
                'Choose the term explicitly. DRAIS never assumes a past term '
                'is still current.',
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text('Decision', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final EnrollmentDecision d in prev == null
                ? <EnrollmentDecision>[EnrollmentDecision.firstTime]
                : <EnrollmentDecision>[
                    EnrollmentDecision.continueSame,
                    EnrollmentDecision.promote,
                    EnrollmentDecision.demote,
                  ])
              ChoiceChip(
                label: Text(d.label),
                selected: _decision == d,
                onSelected: (_) => setState(() {
                  _decision = d;
                  _classId = suggestClassId(d, prev, o.classes) ?? _classId;
                  _streamId = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        picker(
          'Class',
          _classId,
          o.classes,
          (int? v) => setState(() {
            _classId = v;
            _streamId = null;
          }),
        ),
        picker(
          'Stream',
          _streamId,
          streams,
          (int? v) => setState(() => _streamId = v),
          required: false,
        ),
        picker(
          'Academic year',
          _yearId,
          o.academicYears,
          (int? v) => setState(() {
            _yearId = v;
            if (!o.terms.any(
              (TermChoice t) => t.id == _termId && t.academicYearId == v,
            )) {
              _termId = null;
            }
          }),
        ),
        picker(
          'Term',
          _termId,
          terms
              .map(
                (TermChoice t) => Choice(
                  id: t.id,
                  label: t.derivedStatus == 'current' ? '${t.name} (current)' : t.name,
                ),
              )
              .toList(),
          (int? v) => setState(() => _termId = v),
        ),
        picker(
          'Study mode',
          _modeId,
          o.studyModes,
          (int? v) => setState(() => _modeId = v),
        ),
        picker(
          'Curriculum',
          _curriculumId,
          o.curriculums,
          (int? v) => setState(() => _curriculumId = v),
        ),
        picker(
          'Program',
          _programId,
          o.programs,
          (int? v) => setState(() => _programId = v),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.how_to_reg),
          label: Text(_saving ? 'Enrolling…' : 'Enrol'),
          onPressed: _saving ? null : () => _submit(o),
        ),
      ],
    );
  }
}
