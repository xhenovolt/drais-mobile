import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/features/auth/application/auth_state.dart';
import 'package:drais/features/auth/domain/entities/subscription_status.dart';

/// Shown when the credentials are valid but access is withheld.
///
/// Three situations land here, and each needs a different sentence:
///
/// * the school's subscription or trial has lapsed (HTTP 402);
/// * the school is suspended or archived (HTTP 403);
/// * school setup has not been completed (`SETUP_INCOMPLETE`).
///
/// None is fixed by signing in again, which is why the router sends the user
/// here instead of back to the login screen. Being told "invalid credentials"
/// when the credentials were correct is how support tickets get filed against
/// the wrong system.
class AccessBlockedPage extends ConsumerWidget {
  /// Creates the access-blocked page.
  const AccessBlockedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final _BlockedReason reason = _resolve(auth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Access unavailable'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    reason.icon,
                    size: 56,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    reason.title,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    reason.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (auth.user?.school != null) ...<Widget>[
                    const SizedBox(height: 24),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: Text(auth.user!.school!.name),
                        subtitle: Text(auth.user!.email),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.tonal(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).refresh(),
                    child: const Text('Check again'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Chooses the wording from whatever the server told us.
  ///
  /// The server's own message is preferred wherever it exists — it is written
  /// for this exact situation and names the remedy. The fallbacks below cover
  /// the case where we know the state but were given no text.
  static _BlockedReason _resolve(AuthState auth) {
    final Failure? failure = auth.failure;

    if (failure is SubscriptionFailure) {
      return _BlockedReason(
        icon: Icons.card_membership_outlined,
        title: 'Subscription expired',
        message: failure.message,
      );
    }

    final SubscriptionStatus? subscription = auth.user?.subscription;
    if (subscription != null && !subscription.hasAccess) {
      return _BlockedReason(
        icon: Icons.card_membership_outlined,
        title: subscription.isTrial ? 'Trial ended' : 'Subscription expired',
        message:
            'This school\'s DRAIS access has ended. '
            'Contact Xhenvolt or your school administrator to renew.',
      );
    }

    if (auth.requiresSchoolSetup) {
      return const _BlockedReason(
        icon: Icons.settings_outlined,
        title: 'School setup is not finished',
        message:
            'An administrator needs to complete school setup in the '
            'DRAIS web app before the mobile app can be used.',
      );
    }

    if (failure is AuthorizationFailure) {
      return _BlockedReason(
        icon: Icons.block_outlined,
        title: 'Account unavailable',
        message: failure.message,
      );
    }

    return const _BlockedReason(
      icon: Icons.info_outline,
      title: 'Access unavailable',
      message:
          'Your account cannot use DRAIS right now. '
          'Contact your school administrator.',
    );
  }
}

class _BlockedReason {
  const _BlockedReason({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;
}
