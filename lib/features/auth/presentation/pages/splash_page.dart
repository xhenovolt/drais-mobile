import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/constants/app_version.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/features/auth/application/auth_state.dart';
import 'package:drais/shared/widgets/loading_view.dart';

/// Restores the stored session, then hands control to the router.
///
/// This screen navigates nowhere itself. It triggers the restore and the
/// router's redirect does the rest — the same rule as everywhere else in the
/// app, and the reason there is no path to an authenticated screen that
/// bypasses the auth check.
class SplashPage extends ConsumerStatefulWidget {
  /// Creates the splash page.
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    // Deferred to after the first frame: calling a StateNotifier during build
    // would mutate provider state mid-build, which Riverpod rightly rejects.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      final AuthState auth = ref.read(authControllerProvider);
      if (auth.status == AuthStatus.initial) {
        ref.read(authControllerProvider.notifier).restoreSession();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Spacer(),
            Icon(
              Icons.school_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('DRAIS', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              'School management, in your pocket',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            const LoadingView(label: 'Checking your session…'),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                'Version ${AppVersion.fullVersion}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
