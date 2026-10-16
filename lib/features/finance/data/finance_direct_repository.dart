import 'dart:convert';

import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/database/longterm/modules.dart';
import 'package:drais/core/error/api_error_code.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/finance/data/direct/longterm/fee_status.dart';
import 'package:drais/features/finance/domain/finance.dart';

/// Finance, read-only, straight from TiDB — DRAIS LongTerm's finance read
/// routes, in Dart.
///
/// Gated exactly as each route gates itself: `finance.view` or
/// `finance.payments.view`, and the `finance` module switch only where the
/// route checks it (`learners-fees` and `payments` import `checkModule` but
/// never call it; reproduced). `src/lib/finance-permissions.ts`, a
/// role table, is imported by nothing and plays no part.
///
/// Nothing here writes. Recording a payment needs idempotency the internal
/// API does not have (docs/ROADMAP.md).
class FinanceDirectRepository implements FinanceRepository {
  /// Creates the repository.
  FinanceDirectRepository({
    required DraisDatabase database,
    required int schoolId,
    required bool Function(String code) can,
  }) : _db = database,
       _schoolId = schoolId,
       _can = can;

  final DraisDatabase _db;
  final int _schoolId;
  final bool Function(String code) _can;

  Failure? _forbidden(String code) => _can(code)
      ? null
      : AuthorizationFailure(
          code: ApiErrorCode.forbidden,
          message: "Forbidden: missing permission '$code'",
        );

  Future<String> _currency() async {
    final Row? r = await _db.queryOne(
      'SELECT currency FROM schools WHERE id = ? LIMIT 1',
      <Object?>[_schoolId],
    );
    final String? c = SqlValue.asString(r?['currency']);
    return (c == null || c.isEmpty) ? 'UGX' : c;
  }

  static double _d(Object? v) => SqlValue.asDouble(v) ?? 0;

  static String? _s(Row r, String k) {
    final String? v = SqlValue.asString(r[k]);
    return (v == null || v.isEmpty) ? null : v;
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/finance/learners-fees
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<LearnerFeesPage>> learnerFees({
    int? classId,
    int? termId,
    String? search,
    FeeStatus? status,
    int page = 1,
    int limit = 50,
  }) async {
    final Failure? denied = _forbidden('finance.view');
    if (denied != null) return Err<LearnerFeesPage>(denied);
    try {
      // The route fetches every learner and every fee item and sums them in
      // memory. The same sums are taken here in SQL, so one row per learner
      // crosses the network instead of every fee item in the school. The
      // class-structure join is null-safe (<=>) because the route's
      // in-memory grouping matches a learner with no class to fee
      // structures with no class.
      final List<Object?> params = <Object?>[_schoolId];
      final StringBuffer fi = StringBuffer('''
        SELECT sfi.student_id, COUNT(*) AS cnt,
               COALESCE(SUM(sfi.amount), 0) AS amount,
               COALESCE(SUM(sfi.paid), 0) AS paid,
               COALESCE(SUM(sfi.discount), 0) AS discount,
               COALESCE(SUM(sfi.waived), 0) AS waived
          FROM student_fee_items sfi
          JOIN students s_inner ON sfi.student_id = s_inner.id
         WHERE s_inner.school_id = ? AND s_inner.deleted_at IS NULL''');
      if (termId != null) {
        fi.write(' AND sfi.term_id = ?');
        params.add(termId);
      }
      fi.write(' GROUP BY sfi.student_id');

      params.add(_schoolId);
      final StringBuffer fs = StringBuffer('''
        SELECT fs.class_id, COUNT(*) AS cnt, COALESCE(SUM(fs.amount), 0) AS amount
          FROM fee_structures fs
         WHERE fs.school_id = ?''');
      if (termId != null) {
        fs.write(' AND fs.term_id = ?');
        params.add(termId);
      }
      fs.write(' GROUP BY fs.class_id');

      params.add(_schoolId);
      final StringBuffer where = StringBuffer(
        's.school_id = ? AND s.deleted_at IS NULL '
        "AND s.status NOT IN ('dropped_out', 'expelled', 'transferred')",
      );
      if (classId != null) {
        where.write(' AND c.id = ?');
        params.add(classId);
      }
      final String? q = search?.trim();
      if (q != null && q.isNotEmpty) {
        where.write(
          ' AND (LOWER(p.first_name) LIKE ? OR LOWER(p.last_name) LIKE ? OR s.admission_no LIKE ?)',
        );
        params.addAll(<Object?>['%${q.toLowerCase()}%', '%${q.toLowerCase()}%', '%$q%']);
      }

      final List<Object> r = await Future.wait(<Future<Object>>[
        _db.query('''
          SELECT s.id AS student_id, s.admission_no,
                 p.first_name, p.last_name, p.other_name,
                 c.id AS class_id, c.name AS class_name, st.name AS stream_name,
                 fi.cnt AS fi_cnt, fi.amount AS fi_amount, fi.paid AS fi_paid,
                 fi.discount AS fi_discount, fi.waived AS fi_waived,
                 fs.cnt AS fs_cnt, fs.amount AS fs_amount
            FROM students s
            LEFT JOIN people p ON s.person_id = p.id AND p.deleted_at IS NULL
            LEFT JOIN (
              SELECT student_id, MAX(id) AS id FROM enrollments
               WHERE status = 'active' GROUP BY student_id
            ) le ON le.student_id = s.id
            LEFT JOIN enrollments e ON e.id = le.id
            LEFT JOIN classes c ON e.class_id = c.id
            LEFT JOIN streams st ON e.stream_id = st.id
            LEFT JOIN ($fi) fi ON fi.student_id = s.id
            LEFT JOIN ($fs) fs ON fs.class_id <=> c.id
           WHERE $where
           ORDER BY p.last_name, p.first_name
          ''', params),
        _currency(),
      ]);

      final List<LearnerFeeRow> all = <LearnerFeeRow>[];
      for (final Row row in r[0] as List<Row>) {
        final ({
          double? expected,
          double paid,
          double waived,
          double discount,
          double balance,
          FeeStatus status,
        }) t = classifyLearnerFees(
          feeItemsCount: SqlValue.asInt(row['fi_cnt']) ?? 0,
          itemsAmount: _d(row['fi_amount']),
          itemsPaid: _d(row['fi_paid']),
          itemsWaived: _d(row['fi_waived']),
          itemsDiscount: _d(row['fi_discount']),
          classStructureCount: SqlValue.asInt(row['fs_cnt']) ?? 0,
          classStructureAmount: _d(row['fs_amount']),
        );
        if (status != null && t.status != status) continue;
        all.add(
          LearnerFeeRow(
            studentId: SqlValue.asInt(row['student_id']) ?? 0,
            // The route's template literal: `${last} ${first} ${other || ''}`.
            fullName:
                '${SqlValue.asString(row['last_name'])} ${SqlValue.asString(row['first_name'])} ${_s(row, 'other_name') ?? ''}'
                    .trim(),
            admissionNo: _s(row, 'admission_no'),
            classId: SqlValue.asInt(row['class_id']),
            className: _s(row, 'class_name') ?? 'Not Assigned',
            streamName: _s(row, 'stream_name'),
            totalExpected: t.expected,
            totalPaid: t.paid,
            totalWaived: t.waived,
            totalDiscount: t.discount,
            balance: t.balance,
            status: t.status,
            feeItemsCount: SqlValue.asInt(row['fi_cnt']) ?? 0,
          ),
        );
      }

      final int p = page < 1 ? 1 : page;
      final int l = limit.clamp(1, 5000);
      final int start = (p - 1) * l;

      int count(FeeStatus s) => all.where((LearnerFeeRow x) => x.status == s).length;
      double sum(double Function(LearnerFeeRow x) f) =>
          all.fold(0, (double acc, LearnerFeeRow x) => acc + f(x));

      return Ok<LearnerFeesPage>(
        LearnerFeesPage(
          rows: start >= all.length
              ? const <LearnerFeeRow>[]
              : all.sublist(start, (start + l).clamp(0, all.length)),
          summary: FeeSummary(
            totalLearners: all.length,
            totalExpected: sum((LearnerFeeRow x) => x.totalExpected ?? 0),
            totalPaid: sum((LearnerFeeRow x) => x.totalPaid),
            totalBalance: sum((LearnerFeeRow x) => x.balance),
            cleared: count(FeeStatus.cleared),
            partiallyPaid: count(FeeStatus.partiallyPaid),
            unpaid: count(FeeStatus.unpaid),
            undefined: count(FeeStatus.undefined),
          ),
          page: p,
          limit: l,
          total: all.length,
          currency: r[1] as String,
        ),
      );
    } on Failure catch (failure) {
      return Err<LearnerFeesPage>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/finance/student-ledger — getStudentLedger + getStudentBalance
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<StudentLedger>> studentLedger(
    int studentId, {
    int limit = 200,
  }) async {
    try {
      final Failure? off = await checkModule(_db, _schoolId, 'finance');
      if (off != null) return Err<StudentLedger>(off);
      final Failure? denied = _forbidden('finance.view');
      if (denied != null) return Err<StudentLedger>(denied);

      final List<Object> r = await Future.wait(<Future<Object>>[
        _db.query('''
          SELECT sl.id, sl.type, sl.amount, sl.reference, sl.notes, sl.payment_id,
                 CAST(sl.created_at AS CHAR) AS created_at, t.name AS term_name
            FROM student_ledger sl
            LEFT JOIN terms t ON sl.term_id = t.id
           WHERE sl.student_id = ? AND sl.school_id = ?
           ORDER BY sl.created_at DESC
           ${DraisDatabase.limitClause(limit: limit.clamp(1, 500))}
          ''', <Object?>[studentId, _schoolId]),
        _db.queryOne(
          '''
          SELECT COALESCE(SUM(CASE WHEN type = 'debit'  THEN amount ELSE 0 END), 0) AS total_charged,
                 COALESCE(SUM(CASE WHEN type = 'credit' THEN amount ELSE 0 END), 0) AS total_paid,
                 COUNT(*) AS entry_count
            FROM student_ledger WHERE student_id = ? AND school_id = ?
          ''',
          <Object?>[studentId, _schoolId],
        ).then((Row? b) => b ?? const <String, Object?>{}),
        _currency(),
      ]);

      final Row b = r[1] as Row;
      return Ok<StudentLedger>(
        StudentLedger(
          entries: (r[0] as List<Row>)
              .map(
                (Row e) => LedgerEntry(
                  id: SqlValue.asInt(e['id']) ?? 0,
                  isDebit: SqlValue.asString(e['type']) == 'debit',
                  amount: _d(e['amount']),
                  reference: _s(e, 'reference'),
                  termName: _s(e, 'term_name'),
                  notes: _s(e, 'notes'),
                  createdAt: _s(e, 'created_at'),
                  paymentId: SqlValue.asInt(e['payment_id']),
                ),
              )
              .toList(growable: false),
          balance: LedgerBalance(
            totalCharged: _d(b['total_charged']),
            totalPaid: _d(b['total_paid']),
            entryCount: SqlValue.asInt(b['entry_count']) ?? 0,
          ),
          currency: r[2] as String,
        ),
      );
    } on Failure catch (failure) {
      return Err<StudentLedger>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/finance/payments
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<PaymentsPage>> payments({
    int? studentId,
    int limit = 50,
    int offset = 0,
  }) async {
    final Failure? denied = _forbidden('finance.view');
    if (denied != null) return Err<PaymentsPage>(denied);
    try {
      final List<Object?> params = <Object?>[_schoolId];
      String filter = '';
      if (studentId != null) {
        filter = ' AND fp.student_id = ?';
        params.add(studentId);
      }
      final int safeLimit = limit.clamp(1, 1000);
      final int safeOffset = offset < 0 ? 0 : offset;

      // The route joins every active enrolment, ledger credit, receipt and
      // reconciliation directly, so a learner with two active enrolments
      // sees each payment twice. Reproduced; see docs/PARITY.md §4.5.
      final List<Object> r = await Future.wait(<Future<Object>>[
        _db.query('''
          SELECT fp.id, fp.student_id, fp.amount, fp.method, fp.paid_by,
                 fp.reference, fp.receipt_no, CAST(fp.created_at AS CHAR) AS created_at,
                 CONCAT(p.first_name, ' ', p.last_name) AS student_name,
                 s.admission_no, c.name AS class_name, t.name AS term_name,
                 fa.name AS wallet_name, COALESCE(sch.currency, 'UGX') AS currency,
                 pr.status AS reconciliation_status
            FROM finance_payments fp
            JOIN students s ON fp.student_id = s.id AND s.deleted_at IS NULL
            JOIN people p ON s.person_id = p.id AND p.deleted_at IS NULL
            LEFT JOIN enrollments e ON s.id = e.student_id AND e.status = 'active'
            LEFT JOIN classes c ON e.class_id = c.id
            LEFT JOIN student_ledger sl ON sl.payment_id = fp.id AND sl.type = 'credit'
            LEFT JOIN terms t ON sl.term_id = t.id
            LEFT JOIN wallets fa ON fp.account_id = fa.id
            LEFT JOIN schools sch ON fp.school_id = sch.id
            LEFT JOIN receipts r ON fp.id = r.payment_id
            LEFT JOIN payment_reconciliations pr ON fp.id = pr.payment_id
           WHERE fp.school_id = ?$filter
           ORDER BY fp.created_at DESC
           LIMIT $safeLimit OFFSET $safeOffset
          ''', params),
        _db
            .queryOne(
              'SELECT COUNT(*) AS total FROM finance_payments fp WHERE fp.school_id = ?$filter',
              params,
            )
            .then((Row? c) => SqlValue.asInt(c?['total']) ?? 0),
      ]);

      return Ok<PaymentsPage>(
        PaymentsPage(
          total: r[1] as int,
          rows: (r[0] as List<Row>)
              .map(
                (Row row) => PaymentRow(
                  id: SqlValue.asInt(row['id']) ?? 0,
                  studentId: SqlValue.asInt(row['student_id']) ?? 0,
                  amount: _d(row['amount']),
                  currency: _s(row, 'currency') ?? 'UGX',
                  method: _s(row, 'method'),
                  paidBy: _s(row, 'paid_by'),
                  reference: _s(row, 'reference'),
                  receiptNo: _s(row, 'receipt_no'),
                  createdAt: _s(row, 'created_at'),
                  studentName: _s(row, 'student_name'),
                  admissionNo: _s(row, 'admission_no'),
                  className: _s(row, 'class_name'),
                  termName: _s(row, 'term_name'),
                  walletName: _s(row, 'wallet_name'),
                  reconciliationStatus: _s(row, 'reconciliation_status'),
                ),
              )
              .toList(growable: false),
        ),
      );
    } on Failure catch (failure) {
      return Err<PaymentsPage>(failure);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // GET /api/finance/receipts/[ref]
  // ───────────────────────────────────────────────────────────────────────

  @override
  Future<Result<Receipt>> receipt(String ref) async {
    try {
      final Failure? off = await checkModule(_db, _schoolId, 'finance');
      if (off != null) return Err<Receipt>(off);
      final Failure? denied = _forbidden('finance.payments.view');
      if (denied != null) return Err<Receipt>(denied);

      final Row? r = await _db.queryOne(
        '''
        SELECT fp.id AS payment_id, fp.amount, fp.method, fp.reference, fp.notes, fp.receipt_no,
               CAST(fp.created_at AS CHAR) AS paid_at,
               TRIM(CONCAT_WS(' ', p.first_name, p.last_name)) AS learner_name,
               s.admission_no, c.name AS class_name, st.name AS stream_name,
               t.name AS term_name, ay.name AS year_name,
               sch.name AS school_name, sch.address AS school_address,
               sch.phone AS school_phone, sch.email AS school_email, sch.currency,
               r.metadata AS receipt_metadata
          FROM finance_payments fp
          JOIN students s  ON s.id = fp.student_id AND s.school_id = ?
          JOIN people  p   ON p.id = s.person_id
          JOIN schools sch ON sch.id = s.school_id
          LEFT JOIN (SELECT student_id, MAX(id) AS id FROM enrollments
                      WHERE status = 'active' GROUP BY student_id) le ON le.student_id = s.id
          LEFT JOIN enrollments e ON e.id = le.id
          LEFT JOIN classes c  ON c.id = e.class_id
          LEFT JOIN streams st ON st.id = e.stream_id
          LEFT JOIN academic_years ay ON ay.id = e.academic_year_id
          LEFT JOIN (SELECT payment_id, MAX(id) AS id FROM student_ledger
                      WHERE type = 'credit' GROUP BY payment_id) lsl ON lsl.payment_id = fp.id
          LEFT JOIN student_ledger sl ON sl.id = lsl.id
          LEFT JOIN terms t ON t.id = sl.term_id
          LEFT JOIN (SELECT payment_id, MAX(id) AS id FROM receipts GROUP BY payment_id) lr
                 ON lr.payment_id = fp.id
          LEFT JOIN receipts r ON r.id = lr.id
         WHERE (fp.receipt_no = ? OR fp.id = ?) AND fp.school_id = ?
         LIMIT 1
        ''',
        <Object?>[
          _schoolId,
          ref,
          RegExp(r'^\d+$').hasMatch(ref) ? int.parse(ref) : -1,
          _schoolId,
        ],
      );
      if (r == null) {
        return const Err<Receipt>(NotFoundFailure(message: 'Receipt not found'));
      }

      // The route's balance_before / balance_after are NOT reproduced: its
      // "expected" joins student_fee_items.fee_structure_id, which LongTerm's
      // own comments record is never populated, so every receipt shows a
      // balance of minus the learner's total payments. See PARITY §4.5.

      String? receivedBy;
      try {
        final Object? raw = r['receipt_metadata'];
        final Object? meta = raw is String && raw.isNotEmpty ? jsonDecode(raw) : raw;
        final Object? by = meta is Map ? meta['generated_by'] : null;
        if (by != null) {
          final Row? u = await _db.queryOne(
            "SELECT TRIM(CONCAT_WS(' ', first_name, last_name)) AS nm FROM users WHERE id = ? LIMIT 1",
            <Object?>[by],
          );
          receivedBy = _s(u ?? const <String, Object?>{}, 'nm');
        }
      } on Object {
        // As the route: a missing receiver is not an error.
      }

      return Ok<Receipt>(
        Receipt(
          paymentId: SqlValue.asInt(r['payment_id']) ?? 0,
          receiptNo: _s(r, 'receipt_no'),
          amount: _d(r['amount']),
          currency: _s(r, 'currency') ?? 'UGX',
          method: _s(r, 'method'),
          reference: _s(r, 'reference'),
          notes: _s(r, 'notes'),
          paidAt: _s(r, 'paid_at'),
          receivedBy: receivedBy,
          learnerName: _s(r, 'learner_name'),
          admissionNo: _s(r, 'admission_no'),
          className: _s(r, 'class_name'),
          streamName: _s(r, 'stream_name'),
          termName: _s(r, 'term_name'),
          yearName: _s(r, 'year_name'),
          schoolName: _s(r, 'school_name'),
          schoolAddress: _s(r, 'school_address'),
          schoolPhone: _s(r, 'school_phone'),
          schoolEmail: _s(r, 'school_email'),
        ),
      );
    } on Failure catch (failure) {
      return Err<Receipt>(failure);
    }
  }
}
