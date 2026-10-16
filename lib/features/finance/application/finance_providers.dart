import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/finance/domain/finance.dart';

T _unwrap<T>(Result<T> r) => r.fold(
  onOk: (T v) => v,
  onErr: (Failure f) => throw f,
);

/// The fees list for a filter set.
final AutoDisposeFutureProviderFamily<
  LearnerFeesPage,
  ({String? search, FeeStatus? status, int? classId, int limit})
>
learnerFeesProvider = FutureProvider.autoDispose
    .family<
      LearnerFeesPage,
      ({String? search, FeeStatus? status, int? classId, int limit})
    >(
      (
        Ref ref,
        ({String? search, FeeStatus? status, int? classId, int limit}) q,
      ) async => _unwrap(
        await ref
            .watch(financeRepositoryProvider)
            .learnerFees(
              search: q.search,
              status: q.status,
              classId: q.classId,
              limit: q.limit,
            ),
      ),
    );

/// One learner's ledger.
final AutoDisposeFutureProviderFamily<StudentLedger, int> studentLedgerProvider =
    FutureProvider.autoDispose.family<StudentLedger, int>(
      (Ref ref, int studentId) async =>
          _unwrap(await ref.watch(financeRepositoryProvider).studentLedger(studentId)),
    );

/// Payments; one learner's when the key is non-null.
final AutoDisposeFutureProviderFamily<PaymentsPage, ({int? studentId, int limit})>
paymentsProvider = FutureProvider.autoDispose
    .family<PaymentsPage, ({int? studentId, int limit})>(
      (Ref ref, ({int? studentId, int limit}) q) async => _unwrap(
        await ref
            .watch(financeRepositoryProvider)
            .payments(studentId: q.studentId, limit: q.limit),
      ),
    );

/// A receipt by number or payment id.
final AutoDisposeFutureProviderFamily<Receipt, String> receiptProvider =
    FutureProvider.autoDispose.family<Receipt, String>(
      (Ref ref, String ref_) async =>
          _unwrap(await ref.watch(financeRepositoryProvider).receipt(ref_)),
    );
