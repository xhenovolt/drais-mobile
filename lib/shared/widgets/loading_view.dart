import 'package:flutter/material.dart';

/// A centred loading indicator with an optional label.
///
/// The label is not decoration. On the connections DRAIS runs over, a spinner
/// can sit for ten seconds; saying what is happening ("Checking your
/// session…") is the difference between waiting and assuming the app has hung.
class LoadingView extends StatelessWidget {
  /// Creates a loading view.
  const LoadingView({this.label, super.key});

  /// What is being waited for. Written as a sentence the user understands.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          if (label != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              label!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// A dismissible banner for non-fatal notices.
///
/// Used for the subscription-expiry warning and the offline indicator — both
/// situations where the app still works and an error screen would overstate
/// the problem.
class NoticeBanner extends StatelessWidget {
  /// Creates a notice banner.
  const NoticeBanner({
    required this.message,
    this.icon = Icons.info_outline,
    this.tone = NoticeTone.info,
    this.onDismiss,
    super.key,
  });

  /// The text to show.
  final String message;

  /// Leading icon.
  final IconData icon;

  /// Severity, which selects the colour.
  final NoticeTone tone;

  /// Dismiss handler. When null, no close button is shown.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = switch (tone) {
      NoticeTone.info => theme.colorScheme.primaryContainer,
      NoticeTone.warning => theme.colorScheme.tertiaryContainer,
      NoticeTone.error => theme.colorScheme.errorContainer,
    };
    final Color foreground = switch (tone) {
      NoticeTone.info => theme.colorScheme.onPrimaryContainer,
      NoticeTone.warning => theme.colorScheme.onTertiaryContainer,
      NoticeTone.error => theme.colorScheme.onErrorContainer,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: background,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: foreground),
              onPressed: onDismiss,
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// Severity of a [NoticeBanner].
enum NoticeTone {
  /// Neutral information.
  info,

  /// Something needs attention soon — an expiring subscription.
  warning,

  /// Something is wrong but the app still functions — offline mode.
  error,
}
