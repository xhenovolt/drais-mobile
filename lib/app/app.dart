import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/app_router.dart';
import 'package:drais/app/theme/app_theme.dart';
import 'package:drais/app/theme/appearance.dart';
import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/di/providers.dart';

/// The root widget.
///
/// Deliberately thin: it wires the router and the theme and nothing else.
/// Every decision it might otherwise make — where the user may navigate, what
/// the session is, which backend to call — belongs to a provider, so that it
/// can be tested without pumping a widget tree.
class DraisApp extends ConsumerStatefulWidget {
  /// Creates the application root.
  const DraisApp({super.key});

  @override
  ConsumerState<DraisApp> createState() => _DraisAppState();
}

class _DraisAppState extends ConsumerState<DraisApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-read the identity when the app returns to the foreground. A session
    // can die while backgrounded (seven-day expiry, an administrator revoking
    // a role, a school suspended), and finding out on resume is better than
    // finding out through a failed action the user has already committed to.
    if (state == AppLifecycleState.resumed) {
      ref.read(authControllerProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GoRouter router = ref.watch(routerProvider);
    final AppConfig config = ref.watch(appConfigProvider);
    final AppearanceSettings appearance = ref.watch(appearanceProvider);

    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(appearance),
      darkTheme: AppTheme.dark(appearance),
      themeMode: appearance.themeMode,
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        // The user's text scale multiplies the system one rather than
        // replacing it: someone who has enlarged text device-wide for a
        // reason must not have that quietly undone here.
        final MediaQueryData media = MediaQuery.of(context);
        final Widget scaled = MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: appearance.textScale,
              maxScaleFactor: appearance.textScale * 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
        // No environment stripe. It was covering the top-right corner of every
        // screen on a build people are actually using, and the question it
        // answers — which build is this, against what — is answered properly
        // on the About screen, in the drawer footer, and in the copied
        // diagnostics, none of which cost a corner of the UI.
        return scaled;
      },
    );
  }
}
