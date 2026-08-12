import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/setup/data/setup_direct_repository.dart';

/// The minimum a school needs before attendance means anything.
///
/// ## Skippable, deliberately
///
/// A school that has just registered on a phone can leave this and look
/// around. Blocking them behind a form would make the first thing DRAIS ever
/// asks of them a chore — and they may well already be planning to configure
/// properly on a computer.
///
/// Skipping is remembered as *skipped*, not as *done*: the home screen carries
/// a banner naming exactly what is still missing, and this screen stays
/// reachable from it. Nothing is lost; it is just deferred.
///
/// ## Why these three things
///
/// An academic year, one term, and some classes. Without a term there is no
/// period to record attendance against; without classes there is nowhere to
/// put a learner. Everything else the web app configures — curricula,
/// grading, fees, streams — can wait, because attendance does not depend on it.
class SchoolSetupPage extends ConsumerStatefulWidget {
  /// Creates the setup page.
  const SchoolSetupPage({super.key});

  @override
  ConsumerState<SchoolSetupPage> createState() => _SchoolSetupPageState();
}

class _SchoolSetupPageState extends ConsumerState<SchoolSetupPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _year;
  late final TextEditingController _term;

  DateTime _yearStart = DateTime(DateTime.now().year, 1, 1);
  DateTime _yearEnd = DateTime(DateTime.now().year, 12, 31);
  DateTime _termStart = DateTime.now();
  DateTime _termEnd = DateTime.now().add(const Duration(days: 90));

  /// Ugandan secondary levels by default — the commonest shape for a DRAIS
  /// school, and a starting point someone edits rather than invents.
  final List<String> _classes = <String>['S.1', 'S.2', 'S.3', 'S.4'];

  bool _busy = false;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    _year = TextEditingController(text: '${DateTime.now().year}');
    _term = TextEditingController(text: 'Term 1');
  }

  @override
  void dispose() {
    _year.dispose();
    _term.dispose();
    super.dispose();
  }

  Future<void> _pickDate(
    DateTime initial,
    ValueChanged<DateTime> onPicked,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 3),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _finish() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _failure = null;
    });

    final Result<void> result = await ref
        .read(setupRepositoryProvider)
        .apply(
          SchoolSetupDraft(
            academicYearName: _year.text.trim(),
            yearStart: _yearStart,
            yearEnd: _yearEnd,
            termName: _term.text.trim(),
            termStart: _termStart,
            termEnd: _termEnd,
            classNames: _classes,
          ),
        );

    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        // Reload identity so setup_complete propagates and the banner clears.
        await ref.read(authControllerProvider.notifier).refresh();
        ref.invalidate(setupStatusProvider);
        if (mounted) context.go(AppRoutes.home);
      case Err<void>(:final Failure failure):
        setState(() {
          _busy = false;
          _failure = failure;
        });
    }
  }

  void _skip() {
    ref.read(preferencesStoreProvider).setSetupSkipped();
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your school'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : _skip,
            child: const Text('Skip'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Attendance needs a term to record against and classes '
                      'to put learners in. This takes a minute, and you can '
                      'change all of it later.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_failure != null) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _failure!.message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Text('Academic year', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _year,
                      decoration: const InputDecoration(
                        hintText: 'e.g. 2026',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      enabled: !_busy,
                      // The column is varchar(20); a longer value would be
                      // truncated by the database rather than rejected here.
                      maxLength: 20,
                      validator: (String? v) => (v == null || v.trim().isEmpty)
                          ? 'Name the academic year'
                          : null,
                    ),
                    _DateRow(
                      label: 'Year runs',
                      start: _yearStart,
                      end: _yearEnd,
                      enabled: !_busy,
                      onStart: () => _pickDate(
                        _yearStart,
                        (DateTime d) => setState(() => _yearStart = d),
                      ),
                      onEnd: () => _pickDate(
                        _yearEnd,
                        (DateTime d) => setState(() => _yearEnd = d),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text('Current term', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _term,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Term 1',
                        prefixIcon: Icon(Icons.event_note_outlined),
                      ),
                      enabled: !_busy,
                      validator: (String? v) => (v == null || v.trim().isEmpty)
                          ? 'Name the term'
                          : null,
                    ),
                    _DateRow(
                      label: 'Term runs',
                      start: _termStart,
                      end: _termEnd,
                      enabled: !_busy,
                      onStart: () => _pickDate(
                        _termStart,
                        (DateTime d) => setState(() => _termStart = d),
                      ),
                      onEnd: () => _pickDate(
                        _termEnd,
                        (DateTime d) => setState(() => _termEnd = d),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      children: <Widget>[
                        Text('Classes', style: theme.textTheme.titleSmall),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _busy ? null : _addClass,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (int i = 0; i < _classes.length; i++)
                          InputChip(
                            label: Text(_classes[i]),
                            onDeleted: _busy
                                ? null
                                : () => setState(() => _classes.removeAt(i)),
                          ),
                        if (_classes.isEmpty)
                          Text(
                            'No classes yet.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: _busy ? null : _finish,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Finish setup'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : _skip,
                      child: const Text('Skip for now'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addClass() async {
    final TextEditingController controller = TextEditingController();

    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Add a class'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. S.5'),
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (String v) => Navigator.of(context).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    controller.dispose();
    final String? trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      setState(() => _classes.add(trimmed));
    }
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.start,
    required this.end,
    required this.enabled,
    required this.onStart,
    required this.onEnd,
  });

  final String label;
  final DateTime start;
  final DateTime end;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  static String _format(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: enabled ? onStart : null,
            child: Text(_format(start)),
          ),
          Text('→', style: theme.textTheme.bodySmall),
          TextButton(
            onPressed: enabled ? onEnd : null,
            child: Text(_format(end)),
          ),
        ],
      ),
    );
  }
}
