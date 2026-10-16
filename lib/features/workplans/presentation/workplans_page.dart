import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/workplans/domain/workplans.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// Work plans — the web `/work-plans`.
///
/// Same list, status and priority filters, search and create form. Mobile
/// adds updating a plan's status and progress, through the route's own
/// update (which the web page never calls).
class WorkPlansPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const WorkPlansPage({super.key});

  @override
  ConsumerState<WorkPlansPage> createState() => _WorkPlansPageState();
}

class _WorkPlansPageState extends ConsumerState<WorkPlansPage> {
  WorkPlanStatus? _status;
  WorkPlanPriority? _priority;
  String _search = '';
  List<WorkPlan>? _plans;
  Failure? _failure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final Result<List<WorkPlan>> r = await ref
        .read(workPlansRepositoryProvider)
        .list(status: _status, priority: _priority);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (r) {
        case Ok<List<WorkPlan>>(:final List<WorkPlan> value):
          _plans = value;
        case Err<List<WorkPlan>>(:final Failure failure):
          _failure = failure;
      }
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _create() async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: const _CreateForm(),
      ),
    );
    if (saved ?? false) {
      _snack('Work plan created');
      await _load();
    }
  }

  Future<void> _edit(WorkPlan p) async {
    WorkPlanStatus status = p.status;
    double progress = p.progress.toDouble();
    final bool? go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(p.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final WorkPlanStatus s in WorkPlanStatus.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: status == s,
                        onSelected: (_) => set(() {
                          status = s;
                          if (s == WorkPlanStatus.completed) progress = 100;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Progress ${progress.round()}%'),
                Slider(
                  value: progress,
                  max: 100,
                  divisions: 20,
                  label: '${progress.round()}%',
                  onChanged: (double v) => set(() => progress = v),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    final Result<void> r = await ref
        .read(workPlansRepositoryProvider)
        .update(
          WorkPlan(
            id: p.id,
            title: p.title,
            description: p.description,
            ownerType: p.ownerType,
            startDatetime: p.startDatetime,
            endDatetime: p.endDatetime,
            status: status,
            priority: p.priority,
            progress: progress.round(),
            assignedTo: p.assignedTo,
          ),
        );
    if (!mounted) return;
    if (r case Err<void>(:final Failure failure)) {
      _snack(failure.message);
    } else {
      _snack('Work plan updated successfully');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String q = _search.trim().toLowerCase();
    final List<WorkPlan> shown = (_plans ?? const <WorkPlan>[])
        .where(
          (WorkPlan p) =>
              q.isEmpty ||
              p.title.toLowerCase().contains(q) ||
              (p.description ?? '').toLowerCase().contains(q),
        )
        .toList();

    Color statusColor(WorkPlanStatus s) => switch (s) {
      WorkPlanStatus.completed => Colors.green.shade700,
      WorkPlanStatus.inProgress => Colors.blue.shade700,
      WorkPlanStatus.pending => Colors.amber.shade800,
      WorkPlanStatus.cancelled => theme.colorScheme.error,
    };

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Work plans',
        subtitle: '${shown.length} plans',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(148),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search work plans',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (String v) => setState(() => _search = v),
                ),
              ),
              _chips<WorkPlanStatus>(
                WorkPlanStatus.values,
                _status,
                (WorkPlanStatus s) => s.label,
                (WorkPlanStatus? s) {
                  setState(() => _status = s);
                  _load();
                },
                'Any status',
              ),
              _chips<WorkPlanPriority>(
                WorkPlanPriority.values,
                _priority,
                (WorkPlanPriority p) => p.label,
                (WorkPlanPriority? p) {
                  setState(() => _priority = p);
                  _load();
                },
                'Any priority',
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New plan'),
      ),
      body: _loading && _plans == null
          ? const Center(child: CircularProgressIndicator())
          : _failure != null && _plans == null
          ? ErrorView.fromFailure(_failure!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: shown.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(40),
                      children: const <Widget>[
                        Text('No work plans match.', textAlign: TextAlign.center),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: shown.length,
                      itemBuilder: (BuildContext context, int i) {
                        final WorkPlan p = shown[i];
                        return Card(
                          child: InkWell(
                            onTap: () => _edit(p),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          p.title,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                      ),
                                      DraisPill(
                                        label: p.status.label,
                                        color: statusColor(p.status),
                                      ),
                                    ],
                                  ),
                                  if (p.description != null) ...<Widget>[
                                    const SizedBox(height: 4),
                                    Text(
                                      p.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(value: p.progress / 100),
                                  const SizedBox(height: 6),
                                  Text(
                                    <String?>[
                                      '${p.progress}%',
                                      '${p.priority.label} priority',
                                      p.assigneeName,
                                      p.departmentName,
                                      if (p.endDatetime != null)
                                        'due ${p.endDatetime!.split(' ').first}',
                                    ].whereType<String>().join(' · '),
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _chips<T>(
    List<T> values,
    T? selected,
    String Function(T) label,
    ValueChanged<T?> onSelect,
    String anyLabel,
  ) => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 6),
          child: ChoiceChip(
            label: Text(anyLabel),
            selected: selected == null,
            onSelected: (_) => onSelect(null),
          ),
        ),
        for (final T v in values)
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 6),
            child: ChoiceChip(
              label: Text(label(v)),
              selected: selected == v,
              onSelected: (_) => onSelect(v),
            ),
          ),
      ],
    ),
  );
}

class _CreateForm extends ConsumerStatefulWidget {
  const _CreateForm();

  @override
  ConsumerState<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends ConsumerState<_CreateForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  WorkPlanPriority _priority = WorkPlanPriority.medium;
  DateTime? _start;
  DateTime? _end;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// The web's `datetime-local` shape: wall time, no zone.
  static String? _wall(DateTime? d) {
    if (d == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:00';
  }

  Future<DateTime?> _pick(DateTime? initial) async {
    final DateTime now = DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (day == null || !mounted) return null;
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    return DateTime(day.year, day.month, day.day, t?.hour ?? 0, t?.minute ?? 0);
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _err = 'Title is required.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final Result<int> r = await ref
        .read(workPlansRepositoryProvider)
        .create(
          title: _title.text,
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          priority: _priority,
          startDatetime: _wall(_start),
          endDatetime: _wall(_end),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Ok<int>():
        Navigator.of(context).pop(true);
      case Err<int>(:final Failure failure):
        setState(() => _err = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Create work plan', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final WorkPlanPriority p in WorkPlanPriority.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: _priority == p,
                    onSelected: (_) => setState(() => _priority = p),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final DateTime? d = await _pick(_start);
                      if (d != null) setState(() => _start = d);
                    },
                    child: Text(_start == null ? 'Start' : _wall(_start)!.substring(0, 16)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final DateTime? d = await _pick(_end);
                      if (d != null) setState(() => _end = d);
                    },
                    child: Text(_end == null ? 'End' : _wall(_end)!.substring(0, 16)),
                  ),
                ),
              ],
            ),
            if (_err != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Creating…' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }
}
