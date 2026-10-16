import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/timetable/domain/timetable.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// The school timetable, read-only — the web `/academics/timetable` grid,
/// shown a day at a time because five columns do not fit a phone.
///
/// Opens on "My timetable" for a signed-in teacher (the entries route's
/// `teacher_id` filter) and on a class picker otherwise. Editing and
/// auto-generation stay on the web.
class TimetablePage extends ConsumerStatefulWidget {
  /// Creates the page.
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  int? _staffId;
  bool _mine = false;
  int? _classId;
  int? _streamId;
  late int _day = _today();
  TimetableView? _view;
  Failure? _failure;
  bool _loading = true;

  /// Today when it is a school day; Monday at the weekend.
  static int _today() {
    final int wd = schoolWallTime(DateTime.now()).weekday; // 1 = Monday
    return wd >= 1 && wd <= 5 ? wd : 1;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final Result<int?> me = await ref.read(timetableRepositoryProvider).myStaffId();
    if (!mounted) return;
    _staffId = me.valueOrNull;
    _mine = _staffId != null;
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final Result<TimetableView> r = await ref
        .read(timetableRepositoryProvider)
        .load(
          classId: _mine ? null : _classId,
          streamId: _mine ? null : _streamId,
          teacherId: _mine ? _staffId : null,
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (r) {
        case Ok<TimetableView>(:final TimetableView value):
          _view = value;
        case Err<TimetableView>(:final Failure failure):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TimetableView? v = _view;
    final List<TimetableOption> streams = <TimetableOption>[
      for (final TimetableOption s in v?.metadata.streams ?? const <TimetableOption>[])
        if (_classId == null || s.parentId == _classId) s,
    ];

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Timetable',
        subtitle: _mine ? 'My lessons' : 'By class',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                for (final ({int value, String label, String short}) d in timetableDays)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 6),
                    child: ChoiceChip(
                      label: Text(d.short),
                      selected: _day == d.value,
                      onSelected: (_) => setState(() => _day = d.value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            if (_staffId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(value: true, label: Text('My timetable')),
                    ButtonSegment<bool>(value: false, label: Text('By class')),
                  ],
                  selected: <bool>{_mine},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<bool> s) {
                    setState(() => _mine = s.first);
                    _load();
                  },
                ),
              ),
            if (!_mine && v != null) ...<Widget>[
              DropdownButtonFormField<int?>(
                key: ValueKey<String>('class-$_classId'),
                initialValue: _classId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Class',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(child: Text('Choose a class')),
                  for (final TimetableOption c in v.metadata.classes)
                    DropdownMenuItem<int?>(value: c.id, child: Text(c.label)),
                ],
                onChanged: (int? id) {
                  setState(() {
                    _classId = id;
                    _streamId = null;
                  });
                  _load();
                },
              ),
              if (streams.isNotEmpty && _classId != null) ...<Widget>[
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  key: ValueKey<String>('stream-$_classId-$_streamId'),
                  initialValue: _streamId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Stream',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<int?>>[
                    const DropdownMenuItem<int?>(child: Text('All streams')),
                    for (final TimetableOption s in streams)
                      DropdownMenuItem<int?>(value: s.id, child: Text(s.label)),
                  ],
                  onChanged: (int? id) {
                    setState(() => _streamId = id);
                    _load();
                  },
                ),
              ],
              const SizedBox(height: 12),
            ],
            if (v?.cachedAt != null)
              Card(
                color: theme.colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Offline — showing the saved timetable'),
                  subtitle: Text(
                    'Last updated ${describeLocalDate(toLocalDateStr(schoolWallTime(v!.cachedAt!)))} '
                    '${formatClockTime(schoolWallTime(v.cachedAt!))}',
                  ),
                ),
              ),
            if (_loading && v == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failure != null && v == null)
              ErrorView.fromFailure(_failure!, onRetry: _load)
            else if (v != null)
              ..._dayTiles(theme, v),
          ],
        ),
      ),
    );
  }

  List<Widget> _dayTiles(ThemeData theme, TimetableView v) {
    if (!_mine && _classId == null) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(24),
          child: Text('Choose a class to see its timetable.', textAlign: TextAlign.center),
        ),
      ];
    }
    if (v.metadata.periods.isEmpty) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No periods are set up yet. Periods are defined on the web app.',
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return <Widget>[
      for (final TimetablePeriod p in v.metadata.periods)
        if (p.isBreak)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '${p.name}  ${p.timeRange}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          )
        else
          _PeriodTile(period: p, entry: v.at(_day, p.id), mine: _mine),
    ];
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({required this.period, required this.entry, required this.mine});

  final TimetablePeriod period;
  final TimetableEntry? entry;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TimetableEntry? e = entry;
    return Card(
      color: e == null ? theme.colorScheme.surfaceContainerLow : null,
      child: ListTile(
        leading: SizedBox(
          width: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                period.shortName ?? period.name,
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(period.timeRange, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
        title: Text(
          e == null ? 'Free' : (e.subjectName ?? 'Lesson'),
          style: e == null
              ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
              : const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: e == null
            ? null
            : Text(
                <String?>[
                  // A teacher needs the class; a class view needs the teacher.
                  if (mine) <String?>[e.className, e.streamName].whereType<String>().join(' '),
                  if (!mine) e.teacherName,
                  if (e.room != null) 'Room ${e.room}',
                ].whereType<String>().where((String s) => s.isNotEmpty).join(' · '),
              ),
      ),
    );
  }
}
