import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/logging/app_logger.dart';

/// What a school needs before attendance means anything.
class SchoolSetupDraft {
  /// Creates a setup draft.
  const SchoolSetupDraft({
    required this.academicYearName,
    required this.yearStart,
    required this.yearEnd,
    required this.termName,
    required this.termStart,
    required this.termEnd,
    required this.classNames,
  });

  /// e.g. `2026`. The schema caps this at 20 characters.
  final String academicYearName;

  /// When the year begins.
  final DateTime yearStart;

  /// When the year ends.
  final DateTime yearEnd;

  /// e.g. `Term 1`.
  final String termName;

  /// When the term begins.
  final DateTime termStart;

  /// When the term ends.
  final DateTime termEnd;

  /// Class names, in order — `S.1`, `S.2`, and so on.
  final List<String> classNames;
}

/// Writes the minimum a school needs to start using DRAIS.
///
/// ## Why this is minimal on purpose
///
/// The web app's setup covers curricula, programmes, streams, study modes,
/// grading schemes, fee structures and more. Reproducing that on a phone would
/// be a form nobody finishes. This writes the three things without which
/// attendance is meaningless — a year, a term, and some classes — and leaves
/// the rest to the web.
///
/// ## Idempotent by necessity
///
/// Someone will register, skip setup, come back, and run it again. Each step
/// checks for an existing row first, so a second run adds nothing rather than
/// creating a duplicate 2026 or a second Term 1.
class SetupDirectRepository {
  /// Creates the repository.
  SetupDirectRepository({
    required DraisDatabase database,
    required int schoolId,
    required AppLogger logger,
  }) : _db = database,
       _schoolId = schoolId,
       _logger = logger.child('Setup');

  final DraisDatabase _db;
  final int _schoolId;
  final AppLogger _logger;

  /// Applies [draft] and marks the school set up.
  Future<Result<void>> apply(SchoolSetupDraft draft) async {
    try {
      final int yearId = await _ensureAcademicYear(draft);
      await _ensureTerm(draft, yearId);
      await _ensureClasses(draft.classNames);

      // Only now — a school marked complete without a term would let a user
      // into an app whose every screen has nothing to show.
      await _db.execute(
        'UPDATE schools SET setup_complete = TRUE, updated_at = NOW() '
        'WHERE id = ?',
        <Object?>[_schoolId],
      );

      _logger.info(
        'School setup completed.',
        context: <String, Object?>{
          'schoolId': _schoolId,
          'classes': draft.classNames.length,
        },
      );
      return const Ok<void>(null);
    } on Failure catch (failure) {
      return Err<void>(failure);
    }
  }

  /// Whether this school already has a year, a term and at least one class.
  ///
  /// Drives the "you still need to finish setting up" banner, so it reports
  /// what is actually missing rather than trusting `setup_complete` — which a
  /// skip leaves false even after someone has added things on the web.
  Future<Result<SetupStatus>> status() async {
    try {
      final Row? row = await _db.queryOne(
        '''
        SELECT
          (SELECT COUNT(*) FROM academic_years
            WHERE school_id = ? AND deleted_at IS NULL) AS years,
          (SELECT COUNT(*) FROM terms
            WHERE school_id = ? AND deleted_at IS NULL) AS terms,
          (SELECT COUNT(*) FROM classes
            WHERE school_id = ? AND deleted_at IS NULL) AS classes,
          (SELECT setup_complete FROM schools WHERE id = ?) AS complete
        ''',
        <Object?>[_schoolId, _schoolId, _schoolId, _schoolId],
      );

      return Ok<SetupStatus>(
        SetupStatus(
          academicYears: SqlValue.asInt(row?['years']) ?? 0,
          terms: SqlValue.asInt(row?['terms']) ?? 0,
          classes: SqlValue.asInt(row?['classes']) ?? 0,
          markedComplete: SqlValue.asBool(row?['complete']),
        ),
      );
    } on Failure catch (failure) {
      return Err<SetupStatus>(failure);
    }
  }

  Future<int> _ensureAcademicYear(SchoolSetupDraft draft) async {
    final Row? existing = await _db.queryOne(
      'SELECT id FROM academic_years '
      'WHERE school_id = ? AND name = ? AND deleted_at IS NULL LIMIT 1',
      <Object?>[_schoolId, draft.academicYearName],
    );
    final int? found = SqlValue.asInt(existing?['id']);
    if (found != null) return found;

    await _db.execute(
      '''
      INSERT INTO academic_years (school_id, name, start_date, end_date, status)
      VALUES (?, ?, ?, ?, 'active')
      ''',
      <Object?>[
        _schoolId,
        draft.academicYearName,
        draft.yearStart,
        draft.yearEnd,
      ],
    );

    final Row? created = await _db.queryOne(
      'SELECT id FROM academic_years WHERE school_id = ? AND name = ? '
      'ORDER BY id DESC LIMIT 1',
      <Object?>[_schoolId, draft.academicYearName],
    );
    final int? id = SqlValue.asInt(created?['id']);
    if (id == null) {
      throw const ServerFailure(
        message: 'The academic year could not be created.',
        technicalDetail: 'academic_years INSERT produced no readable row',
      );
    }
    return id;
  }

  Future<void> _ensureTerm(SchoolSetupDraft draft, int yearId) async {
    final Row? existing = await _db.queryOne(
      'SELECT id FROM terms WHERE school_id = ? AND academic_year_id = ? '
      'AND name = ? AND deleted_at IS NULL LIMIT 1',
      <Object?>[_schoolId, yearId, draft.termName],
    );
    if (existing != null) return;

    await _db.execute(
      '''
      INSERT INTO terms
        (school_id, name, start_date, end_date, academic_year_id,
         is_active, term_number, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, TRUE, 1, 'active', NOW(), NOW())
      ''',
      <Object?>[
        _schoolId,
        draft.termName,
        draft.termStart,
        draft.termEnd,
        yearId,
      ],
    );
  }

  Future<void> _ensureClasses(List<String> names) async {
    for (int i = 0; i < names.length; i++) {
      final String name = names[i].trim();
      if (name.isEmpty) continue;

      final Row? existing = await _db.queryOne(
        'SELECT id FROM classes '
        'WHERE school_id = ? AND name = ? AND deleted_at IS NULL LIMIT 1',
        <Object?>[_schoolId, name],
      );
      if (existing != null) continue;

      await _db.execute(
        '''
        INSERT INTO classes (school_id, name, level, created_at, updated_at)
        VALUES (?, ?, ?, NOW(), NOW())
        ''',
        <Object?>[_schoolId, name, i + 1],
      );
    }
  }
}

/// What a school has configured so far.
class SetupStatus {
  /// Creates a status.
  const SetupStatus({
    required this.academicYears,
    required this.terms,
    required this.classes,
    required this.markedComplete,
  });

  /// Academic years defined.
  final int academicYears;

  /// Terms defined.
  final int terms;

  /// Classes defined.
  final int classes;

  /// The `schools.setup_complete` flag.
  final bool markedComplete;

  /// Whether the school has everything attendance needs.
  ///
  /// Judged on what exists, not on the flag — someone who skipped here and
  /// then set the school up on the web should not still be nagged.
  bool get isUsable => academicYears > 0 && terms > 0 && classes > 0;

  /// What is still missing, for a nudge that names the gap.
  List<String> get missing => <String>[
    if (academicYears == 0) 'an academic year',
    if (terms == 0) 'a term',
    if (classes == 0) 'classes',
  ];
}
