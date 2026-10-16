import 'package:flutter_test/flutter_test.dart';

import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/formatting/currency.dart';
import 'package:drais/features/finance/data/direct/longterm/fee_status.dart';
import 'package:drais/features/finance/domain/finance.dart';

/// Pins the Finance ports to LongTerm's `src/lib/currency.ts` and
/// `/api/finance/learners-fees`.
void main() {
  group('formatCurrency — the web output, character for character', () {
    test('the documented examples', () {
      expect(formatCurrency(1500000), 'UGX 1,500,000');
      expect(formatCurrency(12.5, 'USD'), r'$ 12.50');
    });

    test('UGX has no decimals and rounds half away from zero', () {
      expect(formatCurrency(1499.5), 'UGX 1,500');
      expect(formatCurrency(-1499.5), 'UGX -1,500');
    });

    test('unknown codes are their own symbol', () {
      expect(formatCurrency(1000, 'ZMW'), 'ZMW 1,000');
      expect(formatCurrency(1000, 'kes'), 'KSh 1,000');
    });

    test('null and non-finite read as zero', () {
      expect(formatCurrency(null), 'UGX 0');
      expect(formatCurrency(double.nan), 'UGX 0');
    });
  });

  group('classifyLearnerFees', () {
    ({
      double? expected,
      double paid,
      double waived,
      double discount,
      double balance,
      FeeStatus status,
    }) c({
      int items = 0,
      double amount = 0,
      double paid = 0,
      double waived = 0,
      double discount = 0,
      int structures = 0,
      double structureAmount = 0,
    }) => classifyLearnerFees(
      feeItemsCount: items,
      itemsAmount: amount,
      itemsPaid: paid,
      itemsWaived: waived,
      itemsDiscount: discount,
      classStructureCount: structures,
      classStructureAmount: structureAmount,
    );

    test('no fee items and no class structure is Undefined', () {
      expect(c().status, FeeStatus.undefined);
    });

    test('fully paid is Cleared', () {
      expect(c(items: 2, amount: 500, paid: 500).status, FeeStatus.cleared);
    });

    test('waivers and discounts count toward clearing', () {
      final r = c(items: 1, amount: 500, paid: 300, waived: 100, discount: 100);
      expect(r.status, FeeStatus.cleared);
      expect(r.balance, 0);
    });

    test('something paid, something owed is Partially Paid', () {
      expect(c(items: 1, amount: 500, paid: 100).status, FeeStatus.partiallyPaid);
    });

    test('a discount alone does not make it partial — the route checks paid/waived', () {
      expect(c(items: 1, amount: 500, discount: 100).status, FeeStatus.unpaid);
    });

    test('an unassigned learner falls back to the class structure', () {
      final r = c(structures: 3, structureAmount: 900);
      expect(r.expected, 900);
      expect(r.status, FeeStatus.unpaid);
      expect(r.balance, 900);
    });

    test('overpayment floors the balance at zero', () {
      final r = c(items: 1, amount: 500, paid: 700);
      expect(r.balance, 0);
      expect(r.status, FeeStatus.cleared);
    });

    test('zero expected is reported as absent, as the route sends undefined', () {
      expect(c(items: 1).expected, isNull);
    });

    test('a defined zero-fee learner is Unpaid, not Cleared', () {
      // `balance <= 0 && totalExpected > 0` — nothing charged is not cleared.
      expect(c(items: 1).status, FeeStatus.unpaid);
    });
  });

  test('stored UTC timestamps parse as UTC', () {
    expect(parseUtcSqlDateTime('2026-10-15 06:00:00'), DateTime.utc(2026, 10, 15, 6));
    expect(parseUtcSqlDateTime('0000-00-00 00:00:00'), isNull);
    expect(parseUtcSqlDateTime(null), isNull);
  });
}
