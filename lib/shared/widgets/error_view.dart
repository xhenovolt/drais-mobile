import 'package:flutter/material.dart';

import 'package:drais/core/config/environment.dart';
import 'package:drais/core/error/failure.dart';

/// The standard way to show a failure.
///
/// Two audiences, one widget — the same split [Failure] itself makes:
/// the user reads [Failure.message] and gets a button to act on; an engineer
/// on a non-production build can expand the technical detail underneath.
///
/// Using this everywhere is what keeps error presentation consistent, and
/// consistency is what stops the app from having twelve different ways of
/// saying "no connection".
class ErrorView extends StatelessWidget {
  /// Creates an error view from explicit text.
  const ErrorView({
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.technicalDetail,
    this.environment = Environment.production,
    this.icon = Icons.error_outline,
    super.key,
  });

  /// Creates an error view from a [Failure], choosing icon and wording to
  /// match the failure kind.
  factory ErrorView.fromFailure(
    Failure failure, {
    VoidCallback? onRetry,
    Environment environment = Environment.production,
    Key? key,
  }) => ErrorView(
    key: key,
    title: _titleFor(failure),
    message: failure.message,
    // Only offer a retry where one could plausibly help. A "try again"
    // button under a permission error is worse than no button: it invites
    // the user to repeat something that will fail identically.
    onRetry: failure.isRetryable ? onRetry : null,
    technicalDetail: failure.technicalDetail,
    environment: environment,
    icon: _iconFor(failure),
  );

  /// Short headline.
  final String title;

  /// User-facing explanation.
  final String message;

  /// Retry handler. When null, no retry button is shown.
  final VoidCallback? onRetry;

  /// Label for the retry button.
  final String retryLabel;

  /// Engineer-facing detail, shown only outside production.
  final String? technicalDetail;

  /// Controls whether [technicalDetail] may be displayed.
  final Environment environment;

  /// Leading icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool showDetail =
        environment.allowsDiagnostics && technicalDetail != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
            if (showDetail) ...<Widget>[
              const SizedBox(height: 24),
              ExpansionTile(
                title: Text(
                  'Technical detail',
                  style: theme.textTheme.labelLarge,
                ),
                subtitle: Text(
                  '${environment.label} build only',
                  style: theme.textTheme.labelSmall,
                ),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      technicalDetail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _titleFor(Failure failure) => switch (failure) {
    NetworkFailure() => 'No connection',
    TimeoutFailure() => 'Server did not respond',
    AuthenticationFailure() => 'Sign-in needed',
    AuthorizationFailure() => 'Not permitted',
    SubscriptionFailure() => 'Subscription expired',
    ValidationFailure() => 'Check your details',
    NotFoundFailure() => 'Not found',
    ConflictFailure() => 'Already exists',
    ServerFailure() => 'Server error',
    MalformedResponseFailure() => 'Unexpected response',
    CancelledFailure() => 'Cancelled',
    UnknownFailure() => 'Something went wrong',
  };

  static IconData _iconFor(Failure failure) => switch (failure) {
    NetworkFailure() => Icons.wifi_off_outlined,
    TimeoutFailure() => Icons.hourglass_disabled_outlined,
    AuthenticationFailure() => Icons.lock_outline,
    AuthorizationFailure() => Icons.block_outlined,
    SubscriptionFailure() => Icons.card_membership_outlined,
    ValidationFailure() => Icons.edit_outlined,
    NotFoundFailure() => Icons.search_off_outlined,
    ConflictFailure() => Icons.copy_outlined,
    ServerFailure() => Icons.cloud_off_outlined,
    MalformedResponseFailure() => Icons.report_gmailerrorred_outlined,
    CancelledFailure() => Icons.cancel_outlined,
    UnknownFailure() => Icons.error_outline,
  };
}
