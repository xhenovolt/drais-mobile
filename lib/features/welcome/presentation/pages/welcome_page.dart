import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/app/theme/app_theme.dart';
import 'package:drais/core/constants/app_version.dart';

/// The first thing a new installation shows.
///
/// ## One screen, once
///
/// Modelled on WhatsApp's welcome: brand, a single sentence, one button. Not a
/// carousel — DRAIS is not discovered in a store. A teacher is handed
/// credentials and told to install it, so slides explaining what a school
/// management system is would answer a question nobody has.
///
/// It is shown **once per installation** and never again, including after
/// sign-out. The flag is device-level, not user-level: the second person to
/// pick up a shared school tablet does not need welcoming to an app that is
/// already in use. Only a reinstall or a data clear brings it back.
class WelcomePage extends ConsumerWidget {
  /// Creates the welcome page.
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient(isDark: isDark),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: <Widget>[
                const Spacer(flex: 3),

                _BrandMark(isDark: isDark),

                const SizedBox(height: 28),
                Text(
                  'Welcome to DRAIS',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Attendance, academics and school records — '
                  'on the device you already carry.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),

                const Spacer(flex: 4),

                FilledButton(
                  // Leads into the slides; the first-run flag is set only when
                  // those finish, so quitting midway shows the flow again.
                  onPressed: () => context.go(AppRoutes.onboarding),
                  child: const Text('Get started'),
                ),

                const SizedBox(height: 16),
                Text(
                  'Already have an account, or registering a school for the '
                  'first time — both start here.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),
                Text(
                  'DRAIS ${AppVersion.semver}  ·  Xhenvolt',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The DRAIS mark.
///
/// A drawn placeholder, not the real logo — there is no brand asset in this
/// repository yet. Replace the child with an `Image.asset` once one exists;
/// the surrounding shape and sizing are what the screen depends on.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color primary = isDark
        ? DraisColors.darkPrimary
        : DraisColors.primary;

    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(26),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: primary.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        Icons.fact_check_outlined,
        size: 52,
        color: isDark ? DraisColors.darkBackground : Colors.white,
      ),
    );
  }
}
