/// Per-learner fee totals and status.
///
/// **Ported from `GET /api/finance/learners-fees`**
/// (`src/app/api/finance/learners-fees/route.ts`, DRAIS LongTerm): the same
/// fallback to the class fee structure, the same balance and the same
/// four-way status, in the same order of tests.
library;

import 'package:drais/features/finance/domain/finance.dart';

/// Totals for one learner, as the route derives them.
({
  double? expected,
  double paid,
  double waived,
  double discount,
  double balance,
  FeeStatus status,
})
classifyLearnerFees({
  required int feeItemsCount,
  required double itemsAmount,
  required double itemsPaid,
  required double itemsWaived,
  required double itemsDiscount,
  required int classStructureCount,
  required double classStructureAmount,
}) {
  double expected = 0;
  double paid = 0;
  double waived = 0;
  double discount = 0;

  if (feeItemsCount > 0) {
    expected = itemsAmount;
    paid = itemsPaid;
    waived = itemsWaived;
    discount = itemsDiscount;
  } else if (classStructureCount > 0) {
    // The class default structure, so an unassigned learner still shows
    // what is expected.
    expected = classStructureAmount;
  }

  final double balance = expected - paid - waived - discount;
  final bool hasDefinition = feeItemsCount > 0 || classStructureCount > 0;

  final FeeStatus status;
  if (!hasDefinition) {
    status = FeeStatus.undefined;
  } else if (balance <= 0 && expected > 0) {
    status = FeeStatus.cleared;
  } else if (paid > 0 || waived > 0) {
    status = FeeStatus.partiallyPaid;
  } else {
    status = FeeStatus.unpaid;
  }

  return (
    // `totalExpected || undefined` — zero is sent as absent.
    expected: expected == 0 ? null : expected,
    paid: paid,
    waived: waived,
    discount: discount,
    // Floored at zero for the row; the status above used the raw value.
    balance: balance > 0 ? balance : 0,
    status: status,
  );
}
