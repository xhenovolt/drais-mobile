import 'package:drais/core/error/result.dart';

/// A learner's fee status — the four values `/api/finance/learners-fees`
/// computes.
enum FeeStatus {
  /// Nothing owed and something was charged.
  cleared('Cleared'),

  /// Something paid or waived, something still owed.
  partiallyPaid('Partially Paid'),

  /// Charged, nothing paid or waived.
  unpaid('Unpaid'),

  /// No fee items and no class fee structure.
  undefined('Undefined');

  const FeeStatus(this.wireValue);

  /// The route's string.
  final String wireValue;
}

/// One learner on the fees list.
class LearnerFeeRow {
  /// Creates a row.
  const LearnerFeeRow({
    required this.studentId,
    required this.fullName,
    required this.className,
    required this.totalPaid,
    required this.totalWaived,
    required this.totalDiscount,
    required this.balance,
    required this.status,
    required this.feeItemsCount,
    this.admissionNo,
    this.classId,
    this.streamName,
    this.totalExpected,
  });

  /// `students.id`.
  final int studentId;

  /// `last first other`, as the route builds it.
  final String fullName;

  /// Admission number.
  final String? admissionNo;

  /// Class, or `Not Assigned`.
  final String className;

  /// Its id.
  final int? classId;

  /// Stream.
  final String? streamName;

  /// Null when zero — the route sends `undefined`.
  final double? totalExpected;

  /// Paid.
  final double totalPaid;

  /// Waived.
  final double totalWaived;

  /// Discounted.
  final double totalDiscount;

  /// Owed, floored at zero.
  final double balance;

  /// Computed status.
  final FeeStatus status;

  /// Fee items assigned.
  final int feeItemsCount;
}

/// The route's `meta` — totals over the whole filtered set.
class FeeSummary {
  /// Creates a summary.
  const FeeSummary({
    this.totalLearners = 0,
    this.totalExpected = 0,
    this.totalPaid = 0,
    this.totalBalance = 0,
    this.cleared = 0,
    this.partiallyPaid = 0,
    this.unpaid = 0,
    this.undefined = 0,
  });

  /// Learners matching.
  final int totalLearners;

  /// Expected across them.
  final double totalExpected;

  /// Paid across them.
  final double totalPaid;

  /// Owed across them.
  final double totalBalance;

  /// Cleared learners.
  final int cleared;

  /// Partially paid learners.
  final int partiallyPaid;

  /// Unpaid learners.
  final int unpaid;

  /// Learners with no fees defined.
  final int undefined;
}

/// One page of the fees list.
class LearnerFeesPage {
  /// Creates a page.
  const LearnerFeesPage({
    required this.rows,
    required this.summary,
    required this.page,
    required this.limit,
    required this.total,
    required this.currency,
  });

  /// `data`.
  final List<LearnerFeeRow> rows;

  /// `meta`.
  final FeeSummary summary;

  /// Page.
  final int page;

  /// Page size.
  final int limit;

  /// Rows across pages.
  final int total;

  /// `schools.currency`.
  final String currency;

  /// Whether another page exists.
  bool get hasMore => page * limit < total;
}

/// One `student_ledger` entry.
class LedgerEntry {
  /// Creates an entry.
  const LedgerEntry({
    required this.id,
    required this.isDebit,
    required this.amount,
    this.reference,
    this.termName,
    this.notes,
    this.createdAt,
    this.paymentId,
  });

  /// Row id.
  final int id;

  /// Debit = a charge; credit = a payment.
  final bool isDebit;

  /// Amount.
  final double amount;

  /// Reference.
  final String? reference;

  /// Term.
  final String? termName;

  /// Notes.
  final String? notes;

  /// `created_at` as stored.
  final String? createdAt;

  /// The payment a credit came from.
  final int? paymentId;
}

/// `getStudentBalance()` — SUM(debit) − SUM(credit) over the ledger.
class LedgerBalance {
  /// Creates a balance.
  const LedgerBalance({
    this.totalCharged = 0,
    this.totalPaid = 0,
    this.entryCount = 0,
  });

  /// SUM(debit).
  final double totalCharged;

  /// SUM(credit).
  final double totalPaid;

  /// Ledger rows.
  final int entryCount;

  /// Positive means the learner owes.
  double get balance => totalCharged - totalPaid;
}

/// `GET /api/finance/student-ledger`.
class StudentLedger {
  /// Creates a ledger.
  const StudentLedger({
    required this.entries,
    required this.balance,
    required this.currency,
  });

  /// Newest first.
  final List<LedgerEntry> entries;

  /// The calculated balance.
  final LedgerBalance balance;

  /// `schools.currency`.
  final String currency;
}

/// One payment — a row of `GET /api/finance/payments`.
class PaymentRow {
  /// Creates a row.
  const PaymentRow({
    required this.id,
    required this.studentId,
    required this.amount,
    required this.currency,
    this.method,
    this.paidBy,
    this.reference,
    this.receiptNo,
    this.createdAt,
    this.studentName,
    this.admissionNo,
    this.className,
    this.termName,
    this.walletName,
    this.reconciliationStatus,
  });

  /// `finance_payments.id`.
  final int id;

  /// The learner.
  final int studentId;

  /// Amount.
  final double amount;

  /// Currency.
  final String currency;

  /// Cash, mobile money, bank…
  final String? method;

  /// Who paid.
  final String? paidBy;

  /// External reference.
  final String? reference;

  /// Receipt number.
  final String? receiptNo;

  /// When.
  final String? createdAt;

  /// Learner name.
  final String? studentName;

  /// Admission number.
  final String? admissionNo;

  /// Class.
  final String? className;

  /// Term, from the ledger credit.
  final String? termName;

  /// Wallet / account.
  final String? walletName;

  /// `payment_reconciliations.status`.
  final String? reconciliationStatus;
}

/// One page of payments.
class PaymentsPage {
  /// Creates a page.
  const PaymentsPage({required this.rows, required this.total});

  /// Newest first.
  final List<PaymentRow> rows;

  /// Payments matching.
  final int total;
}

/// `GET /api/finance/receipts/[ref]`.
class Receipt {
  /// Creates a receipt.
  const Receipt({
    required this.paymentId,
    required this.amount,
    required this.currency,
    this.receiptNo,
    this.method,
    this.reference,
    this.notes,
    this.paidAt,
    this.receivedBy,
    this.learnerName,
    this.admissionNo,
    this.className,
    this.streamName,
    this.termName,
    this.yearName,
    this.schoolName,
    this.schoolAddress,
    this.schoolPhone,
    this.schoolEmail,
  });

  /// Payment.
  final int paymentId;

  /// Receipt number.
  final String? receiptNo;

  /// Amount.
  final double amount;

  /// Currency.
  final String currency;

  /// Method.
  final String? method;

  /// Reference.
  final String? reference;

  /// Notes.
  final String? notes;

  /// When.
  final String? paidAt;

  /// The user who generated the receipt.
  final String? receivedBy;

  /// Learner.
  final String? learnerName;

  /// Admission number.
  final String? admissionNo;

  /// Class.
  final String? className;

  /// Stream.
  final String? streamName;

  /// Term.
  final String? termName;

  /// Academic year.
  final String? yearName;

  /// School.
  final String? schoolName;

  /// School address.
  final String? schoolAddress;

  /// School phone.
  final String? schoolPhone;

  /// School email.
  final String? schoolEmail;
}

/// Finance, read-only.
///
/// | Method | LongTerm source |
/// |---|---|
/// | [learnerFees] | `GET /api/finance/learners-fees` |
/// | [studentLedger] | `GET /api/finance/student-ledger` |
/// | [payments] | `GET /api/finance/payments` |
/// | [receipt] | `GET /api/finance/receipts/[ref]` |
abstract interface class FinanceRepository {
  /// The fees list with its school-wide summary.
  Future<Result<LearnerFeesPage>> learnerFees({
    int? classId,
    int? termId,
    String? search,
    FeeStatus? status,
    int page = 1,
    int limit = 50,
  });

  /// One learner's ledger and calculated balance.
  Future<Result<StudentLedger>> studentLedger(int studentId, {int limit = 200});

  /// Payments, newest first; one learner's when [studentId] is given.
  Future<Result<PaymentsPage>> payments({
    int? studentId,
    int limit = 50,
    int offset = 0,
  });

  /// A receipt by receipt number or payment id.
  Future<Result<Receipt>> receipt(String ref);
}
