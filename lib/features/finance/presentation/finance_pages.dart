import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/formatting/currency.dart';
import 'package:drais/features/finance/application/finance_providers.dart';
import 'package:drais/features/finance/domain/finance.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/error_view.dart';

String _messageOf(Object e) =>
    e is Failure ? e.message : 'Something went wrong.';

/// A stored `created_at` (UTC) as school-local date and time.
String _when(String? raw) {
  final DateTime? at = parseUtcSqlDateTime(raw);
  if (at == null) return '';
  final DateTime wall = schoolWallTime(at);
  return '${describeLocalDate(toLocalDateStr(wall))} ${formatClockTime(wall)}';
}

Color _statusColor(ThemeData t, FeeStatus s) => switch (s) {
  FeeStatus.cleared => Colors.green.shade700,
  FeeStatus.partiallyPaid => t.colorScheme.tertiary,
  FeeStatus.unpaid => t.colorScheme.error,
  FeeStatus.undefined => t.colorScheme.onSurfaceVariant,
};

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Learner fees — the web /finance/learners-fees
// ─────────────────────────────────────────────────────────────────────────

/// Every learner's fee position, with the school-wide totals.
class FeesPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const FeesPage({super.key});

  @override
  ConsumerState<FeesPage> createState() => _FeesPageState();
}

class _FeesPageState extends ConsumerState<FeesPage> {
  String? _search;
  FeeStatus? _status;
  int _limit = 50;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ({String? search, FeeStatus? status, int? classId, int limit}) key = (
      search: _search,
      status: _status,
      classId: null,
      limit: _limit,
    );
    final AsyncValue<LearnerFeesPage> fees = ref.watch(learnerFeesProvider(key));

    return Scaffold(
      appBar: DraisAppBar(
        title: 'Learner fees',
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Payments',
            onPressed: () => context.push(AppRoutes.payments),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search name or admission number',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (String v) => setState(() {
                    _search = v.trim().isEmpty ? null : v.trim();
                    _limit = 50;
                  }),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 6),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _status == null,
                        onSelected: (_) => setState(() => _status = null),
                      ),
                    ),
                    for (final FeeStatus s in FeeStatus.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 6),
                        child: ChoiceChip(
                          label: Text(s.wireValue),
                          selected: _status == s,
                          onSelected: (_) => setState(() {
                            _status = s;
                            _limit = 50;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: fees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => ErrorView(
          title: 'Could not load fees',
          message: _messageOf(e),
          onRetry: () => ref.invalidate(learnerFeesProvider(key)),
        ),
        data: (LearnerFeesPage p) {
          final FeeSummary s = p.summary;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(learnerFeesProvider(key)),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: p.rows.length + 2,
              itemBuilder: (BuildContext context, int i) {
                if (i == 0) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              _Stat('Expected', formatCurrency(s.totalExpected, p.currency)),
                              _Stat(
                                'Paid',
                                formatCurrency(s.totalPaid, p.currency),
                                color: Colors.green.shade700,
                              ),
                              _Stat(
                                'Outstanding',
                                formatCurrency(s.totalBalance, p.currency),
                                color: theme.colorScheme.error,
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            children: <Widget>[
                              _Stat('Cleared', '${s.cleared}'),
                              _Stat('Partial', '${s.partiallyPaid}'),
                              _Stat('Unpaid', '${s.unpaid}'),
                              _Stat('No fees set', '${s.undefined}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (i == p.rows.length + 1) {
                  return p.hasMore
                      ? TextButton(
                          onPressed: () => setState(() => _limit += 50),
                          child: Text('Show more (${p.total - p.rows.length} left)'),
                        )
                      : const SizedBox.shrink();
                }
                final LearnerFeeRow r = p.rows[i - 1];
                return Card(
                  child: ListTile(
                    title: Text(r.fullName.isEmpty ? 'Learner #${r.studentId}' : r.fullName),
                    subtitle: Text(
                      <String?>[r.className, r.admissionNo, r.status.wireValue]
                          .whereType<String>()
                          .join(' · '),
                    ),
                    trailing: Text(
                      formatCurrency(r.balance, p.currency),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: _statusColor(theme, r.status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => context.push(
                      AppRoutes.learnerFinancePath(r.studentId, name: r.fullName),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// One learner — /api/finance/student-ledger + /api/finance/payments
// ─────────────────────────────────────────────────────────────────────────

/// One learner's ledger, balance and payments.
class LearnerFinancePage extends ConsumerWidget {
  /// Creates the page.
  const LearnerFinancePage({required this.studentId, this.name, super.key});

  /// `students.id`.
  final int studentId;

  /// Shown in the title.
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<StudentLedger> ledger = ref.watch(
      studentLedgerProvider(studentId),
    );
    final AsyncValue<PaymentsPage> payments = ref.watch(
      paymentsProvider((studentId: studentId, limit: 50)),
    );

    return Scaffold(
      appBar: DraisAppBar(title: name ?? 'Fees', subtitle: 'Fees & payments'),
      body: ledger.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => ErrorView(
          title: 'Could not load fees',
          message: _messageOf(e),
          onRetry: () => ref.invalidate(studentLedgerProvider(studentId)),
        ),
        data: (StudentLedger l) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    _Stat('Charged', formatCurrency(l.balance.totalCharged, l.currency)),
                    _Stat(
                      'Paid',
                      formatCurrency(l.balance.totalPaid, l.currency),
                      color: Colors.green.shade700,
                    ),
                    _Stat(
                      l.balance.balance >= 0 ? 'Owes' : 'In credit',
                      formatCurrency(l.balance.balance.abs(), l.currency),
                      color: l.balance.balance > 0 ? theme.colorScheme.error : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Payments', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            payments.when(
              loading: () => const LinearProgressIndicator(),
              error: (Object e, StackTrace _) => Text(_messageOf(e)),
              data: (PaymentsPage p) => p.rows.isEmpty
                  ? const Text('No payments recorded.')
                  : Column(
                      children: <Widget>[
                        for (final PaymentRow pay in p.rows) _PaymentTile(pay: pay),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            Text('Ledger', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            if (l.entries.isEmpty) const Text('No ledger entries.'),
            for (final LedgerEntry e in l.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  e.isDebit ? Icons.north_east : Icons.south_west,
                  color: e.isDebit ? theme.colorScheme.error : Colors.green.shade700,
                ),
                title: Text(e.reference ?? (e.isDebit ? 'Charge' : 'Payment')),
                subtitle: Text(
                  <String?>[e.termName, _when(e.createdAt), e.notes]
                      .whereType<String>()
                      .where((String s) => s.isNotEmpty)
                      .join(' · '),
                ),
                trailing: Text(
                  '${e.isDebit ? '+' : '−'} ${formatCurrency(e.amount, l.currency)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.pay, this.showLearner = false});

  final PaymentRow pay;
  final bool showLearner;

  @override
  Widget build(BuildContext context) {
    final String ref = pay.receiptNo ?? '${pay.id}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text(formatCurrency(pay.amount, pay.currency)),
        subtitle: Text(
          <String?>[
            if (showLearner) pay.studentName,
            pay.method,
            pay.termName,
            _when(pay.createdAt),
            pay.receiptNo,
          ].whereType<String>().where((String s) => s.isNotEmpty).join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(AppRoutes.receiptPath(ref)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Payments — the web /finance/payments (read-only)
// ─────────────────────────────────────────────────────────────────────────

/// Recent payments across the school.
class PaymentsListPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const PaymentsListPage({super.key});

  @override
  ConsumerState<PaymentsListPage> createState() => _PaymentsListPageState();
}

class _PaymentsListPageState extends ConsumerState<PaymentsListPage> {
  int _limit = 50;

  @override
  Widget build(BuildContext context) {
    final ({int? studentId, int limit}) key = (studentId: null, limit: _limit);
    final AsyncValue<PaymentsPage> page = ref.watch(paymentsProvider(key));
    return Scaffold(
      appBar: DraisAppBar(
        title: 'Payments',
        subtitle: page.maybeWhen(
          data: (PaymentsPage p) => '${p.total} payments · view only',
          orElse: () => null,
        ),
      ),
      body: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => ErrorView(
          title: 'Could not load payments',
          message: _messageOf(e),
          onRetry: () => ref.invalidate(paymentsProvider(key)),
        ),
        data: (PaymentsPage p) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Text(
              'Payments are recorded on the web app for now — a payment sent '
              'twice over a bad connection would be recorded twice.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final PaymentRow pay in p.rows) _PaymentTile(pay: pay, showLearner: true),
            if (p.rows.length < p.total && _limit < 1000)
              TextButton(
                onPressed: () => setState(() => _limit += 50),
                child: const Text('Show more'),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Receipt — the web /finance/receipts/[receiptNo]
// ─────────────────────────────────────────────────────────────────────────

/// One receipt.
class ReceiptPage extends ConsumerWidget {
  /// Creates the page.
  const ReceiptPage({required this.reference, super.key});

  /// Receipt number or payment id.
  final String reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<Receipt> receipt = ref.watch(receiptProvider(reference));

    Widget line(String label, String? value) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(child: Text(value)),
              ],
            ),
          );

    return Scaffold(
      appBar: const DraisAppBar(title: 'Receipt'),
      body: receipt.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) => ErrorView(
          title: 'Could not load this receipt',
          message: _messageOf(e),
          onRetry: () => ref.invalidate(receiptProvider(reference)),
        ),
        data: (Receipt r) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(r.schoolName ?? '', style: theme.textTheme.titleMedium),
                    if (r.schoolAddress != null) Text(r.schoolAddress!),
                    if (r.schoolPhone != null || r.schoolEmail != null)
                      Text(
                        <String?>[r.schoolPhone, r.schoolEmail]
                            .whereType<String>()
                            .join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    const Divider(height: 24),
                    Center(
                      child: Text(
                        formatCurrency(r.amount, r.currency),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    line('Receipt no.', r.receiptNo ?? '#${r.paymentId}'),
                    line('Learner', r.learnerName),
                    line('Admission no.', r.admissionNo),
                    line(
                      'Class',
                      <String?>[r.className, r.streamName].whereType<String>().join(' · '),
                    ),
                    line(
                      'Term',
                      <String?>[r.termName, r.yearName].whereType<String>().join(' · '),
                    ),
                    line('Method', r.method),
                    line('Reference', r.reference),
                    line('Paid', _when(r.paidAt)),
                    line('Received by', r.receivedBy),
                    line('Notes', r.notes),
                    const Divider(height: 24),
                    Text(
                      // The web receipt's balance lines are omitted
                      // deliberately: the platform computes them from a
                      // column it never fills, so they are always wrong.
                      'Balance is not shown on this receipt — see the '
                      "learner's fees for the current balance.",
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
