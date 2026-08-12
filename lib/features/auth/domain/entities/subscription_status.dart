/// The school's DRAIS subscription state.
///
/// Mirrors the `subscription` object from `/api/auth/me`, computed server-side
/// by `getSubscriptionInfo()` in `src/lib/subscription.ts`.
///
/// ## The client computes nothing here
///
/// Every field is read from the server as-is. It would be trivial to derive
/// `hasAccess` from `expiresAt` on the device, and it would be wrong: the
/// server owns the rule (which distinguishes trial from paid, and treats an
/// open-ended active subscription as never expiring), a device clock can be
/// hours off or deliberately set back, and duplicating the logic guarantees
/// the two implementations eventually disagree. Access decisions live on the
/// server; this class only reports them.
class SubscriptionStatus {
  /// Creates a subscription status.
  const SubscriptionStatus({
    required this.status,
    required this.hasAccess,
    this.type,
    this.trialEndDate,
    this.trialDaysRemaining,
    this.subscriptionEndDate,
    this.subscriptionDaysRemaining,
    this.daysUntilExpiry,
    this.expiringSoon = false,
  });

  /// `schools.subscription_status`: `active` | `trial` | `expired` | `inactive`.
  final String status;

  /// Whether the backend currently grants access. **Authoritative.**
  final bool hasAccess;

  /// Plan type, when the backend reports one.
  final String? type;

  /// When the free trial ends.
  final DateTime? trialEndDate;

  /// Days left in the trial, as counted by the server.
  final int? trialDaysRemaining;

  /// When the paid subscription ends. Null means open-ended.
  final DateTime? subscriptionEndDate;

  /// Days left on the paid subscription, as counted by the server.
  final int? subscriptionDaysRemaining;

  /// Days until whichever of the two dates applies.
  final int? daysUntilExpiry;

  /// Whether the server flagged this as expiring soon — the trigger for the
  /// renewal banner. Login also returns a `warning` object saying the same.
  final bool expiringSoon;

  /// Whether the school is on a trial rather than a paid plan.
  bool get isTrial => status.toLowerCase() == 'trial';

  /// The effective end date, preferring the paid subscription.
  DateTime? get effectiveEndDate => subscriptionEndDate ?? trialEndDate;

  @override
  String toString() =>
      'SubscriptionStatus($status, hasAccess: $hasAccess, '
      'daysUntilExpiry: $daysUntilExpiry)';
}
