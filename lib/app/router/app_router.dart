import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/features/about/presentation/pages/about_page.dart';
import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/config/data_mode.dart';
import 'package:drais/core/config/server_config.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/features/auth/application/auth_state.dart';
import 'package:drais/features/auth/presentation/pages/access_blocked_page.dart';
import 'package:drais/features/auth/presentation/pages/change_password_page.dart';
import 'package:drais/features/auth/presentation/pages/login_page.dart';
import 'package:drais/features/auth/presentation/pages/register_school_page.dart';
import 'package:drais/features/auth/presentation/pages/splash_page.dart';
import 'package:drais/app/shell/app_shell.dart';
import 'package:drais/features/attendance/presentation/pages/attendance_log_page.dart';
import 'package:drais/features/attendance/presentation/pages/attendance_trends_page.dart';
import 'package:drais/features/attendance/presentation/pages/unmatched_punches_page.dart';
import 'package:drais/features/home/presentation/pages/home_page.dart';
import 'package:drais/features/profile/presentation/pages/profile_page.dart';
import 'package:drais/features/students/presentation/pages/student_detail_page.dart';
import 'package:drais/features/students/presentation/pages/students_page.dart';
import 'package:drais/features/timehealth/presentation/pages/time_health_page.dart';
import 'package:drais/features/settings/presentation/pages/appearance_page.dart';
import 'package:drais/features/setup/presentation/pages/school_setup_page.dart';
import 'package:drais/features/server/presentation/pages/connect_server_page.dart';
import 'package:drais/features/welcome/presentation/pages/onboarding_page.dart';
import 'package:drais/features/welcome/presentation/pages/welcome_page.dart';
import 'package:drais/features/diagnostics/presentation/pages/diagnostics_page.dart';
import 'package:drais/shared/widgets/error_view.dart';

/// The application router.
///
/// ## One place decides where you may be
///
/// Every authentication gate is expressed as a redirect here, not as a `push`
/// scattered through screens. A screen that navigates on its own is a screen
/// that can be reached by another path that forgot to check — which is how
/// authenticated views end up briefly visible to signed-out users. The
/// redirect runs on every navigation *and* on every auth state change, so
/// there is no such gap.
///
/// This mirrors the role LongTerm's `middleware.ts` plays for the web app,
/// including its `PUBLIC_ROUTES`, its forced-password-change redirect, and its
/// setup gate.
///
/// **These are UX gates, not security.** Reaching a route is not the same as
/// being served data: every API call is authorized independently by the
/// server. A tampered client gets prettier screens and identical 403s.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);

  // A ValueNotifier bridge, rather than watching auth state in this provider:
  // rebuilding the GoRouter on every auth change would tear down the whole
  // navigator and lose the back stack. `refreshListenable` re-evaluates the
  // redirect in place instead.
  final _AuthRefreshNotifier refreshNotifier = _AuthRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: config.environment.allowsDiagnostics,
    refreshListenable: refreshNotifier,
    redirect: (BuildContext context, GoRouterState state) =>
        _redirect(ref, state),
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: ErrorView(
        title: 'Page not found',
        message: 'No screen matches ${state.uri.path}.',
        onRetry: () => context.go(AppRoutes.dashboard),
        retryLabel: 'Go to dashboard',
      ),
    ),
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        name: AppRoutes.splashName,
        builder: (BuildContext context, GoRouterState state) =>
            const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        name: AppRoutes.welcomeName,
        builder: (BuildContext context, GoRouterState state) =>
            const WelcomePage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: AppRoutes.onboardingName,
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.connect,
        name: AppRoutes.connectName,
        builder: (BuildContext context, GoRouterState state) =>
            const ConnectServerPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.loginName,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.registerSchool,
        name: AppRoutes.registerSchoolName,
        builder: (BuildContext context, GoRouterState state) =>
            const RegisterSchoolPage(),
      ),
      GoRoute(
        path: AppRoutes.schoolSetup,
        name: AppRoutes.schoolSetupName,
        builder: (BuildContext context, GoRouterState state) =>
            const SchoolSetupPage(),
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        name: AppRoutes.changePasswordName,
        builder: (BuildContext context, GoRouterState state) =>
            const ChangePasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.accessBlocked,
        name: AppRoutes.accessBlockedName,
        builder: (BuildContext context, GoRouterState state) =>
            const AccessBlockedPage(),
      ),
      // The signed-in app lives inside a shell, so the bottom bar and drawer
      // are always present. Each branch keeps its own navigator: scroll
      // position and depth survive a tab switch, which is most of what makes
      // an app feel native rather than like a series of pushed pages.
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell navigationShell,
            ) => AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.home,
                name: AppRoutes.homeName,
                builder: (BuildContext context, GoRouterState state) =>
                    const HomePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.attendanceLog,
                name: AppRoutes.attendanceLogName,
                builder: (BuildContext context, GoRouterState state) =>
                    const AttendanceLogPage(),
                routes: <RouteBase>[
                  // Nested so both open inside the Attendance tab and the
                  // bottom bar stays put.
                  GoRoute(
                    path: 'trends',
                    name: AppRoutes.attendanceTrendsName,
                    builder: (BuildContext context, GoRouterState state) =>
                        const AttendanceTrendsPage(),
                  ),
                  GoRoute(
                    path: 'unmatched',
                    name: AppRoutes.unmatchedPunchesName,
                    builder: (BuildContext context, GoRouterState state) =>
                        const UnmatchedPunchesPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.timeHealth,
                name: AppRoutes.timeHealthName,
                builder: (BuildContext context, GoRouterState state) =>
                    const TimeHealthPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.students,
                name: AppRoutes.studentsName,
                builder: (BuildContext context, GoRouterState state) =>
                    const StudentsPage(),
                routes: <RouteBase>[
                  // Nested, so a learner opens *inside* the Students tab and
                  // the bottom bar stays put — leaving the shell to view a
                  // learner would feel like leaving the app.
                  GoRoute(
                    path: ':id',
                    name: AppRoutes.studentDetailName,
                    builder: (BuildContext context, GoRouterState state) {
                      final int? id = int.tryParse(
                        state.pathParameters['id'] ?? '',
                      );
                      if (id == null) {
                        return const StudentsPage();
                      }
                      return StudentDetailPage(studentId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Reached from the drawer, so they sit above the shell and cover the
      // bottom bar — they are destinations you leave, not places you live.
      GoRoute(
        path: AppRoutes.profile,
        name: AppRoutes.profileName,
        builder: (BuildContext context, GoRouterState state) =>
            const ProfilePage(),
      ),
      GoRoute(
        path: AppRoutes.appearance,
        name: AppRoutes.appearanceName,
        builder: (BuildContext context, GoRouterState state) =>
            const AppearancePage(),
      ),
      GoRoute(
        path: AppRoutes.about,
        name: AppRoutes.aboutName,
        builder: (BuildContext context, GoRouterState state) =>
            const AboutPage(),
      ),
      GoRoute(
        path: AppRoutes.diagnostics,
        name: AppRoutes.diagnosticsName,
        builder: (BuildContext context, GoRouterState state) =>
            const DiagnosticsPage(),
      ),
    ],
  );
});

/// Decides where the user is allowed to be, given the current auth state.
///
/// Returning null means "stay put". Every branch below either returns null or
/// a route the user is definitely permitted to reach — a redirect that could
/// itself be redirected would loop.
String? _redirect(Ref ref, GoRouterState state) {
  final AuthState auth = ref.read(authControllerProvider);
  final String location = state.matchedLocation;

  // The welcome comes before everything, including server selection: a fresh
  // installation should say hello before it asks for anything. Once accepted
  // it is never shown again, so this branch is dead for the entire life of the
  // install after the first launch.
  if (!ref.read(welcomeSeenProvider)) {
    // Free movement within the first-run flow — welcome leads to the slides,
    // and the slides may be skipped. Anywhere else redirects back to the start.
    return AppRoutes.firstRun.contains(location) ? null : AppRoutes.welcome;
  }
  if (AppRoutes.firstRun.contains(location)) return AppRoutes.splash;

  // Server selection is the next gate — but only in API mode. In direct
  // mode the app talks to TiDB itself, so there is no address to ask for and
  // the connect screen would be a dead end.
  final bool needsServer = ref.read(dataModeProvider) == DataMode.api;
  final bool hasServer = ref.read(serverControllerProvider) != null;
  if (needsServer && !hasServer) {
    return location == AppRoutes.connect ? null : AppRoutes.connect;
  }
  // Nothing to configure any more, so the connect screen is not a place to sit.
  if (location == AppRoutes.connect) return AppRoutes.splash;

  switch (auth.status) {
    // Still deciding — hold the splash screen. Redirecting anywhere now would
    // show the login screen for a frame before the session resolves.
    case AuthStatus.initial:
    case AuthStatus.restoring:
      return location == AppRoutes.splash ? null : AppRoutes.splash;

    case AuthStatus.authenticating:
      return null;

    case AuthStatus.unauthenticated:
      return AppRoutes.public.contains(location) && location != AppRoutes.splash
          ? null
          : AppRoutes.login;

    // A session exists but could not be verified. The user keeps their
    // session and the app proceeds; screens show cached data and an offline
    // banner. Forcing a sign-out here would strand a teacher with no signal.
    case AuthStatus.offlineUnverified:
      return location == AppRoutes.splash ? AppRoutes.dashboard : null;

    case AuthStatus.blocked:
      // Ordered by what the user can actually act on: changing a password is
      // in their hands, renewing a subscription is not.
      if (auth.requiresPasswordChange) {
        return location == AppRoutes.changePassword
            ? null
            : AppRoutes.changePassword;
      }
      return location == AppRoutes.accessBlocked
          ? null
          : AppRoutes.accessBlocked;

    case AuthStatus.authenticated:
      // A school that has never been configured is offered setup once. Skip
      // records a preference, and this stops firing — the home banner takes
      // over the nagging, which is the polite version of the same reminder.
      final bool offerSetup =
          auth.requiresSchoolSetup &&
          !ref.read(preferencesStoreProvider).setupSkipped;
      if (offerSetup && location != AppRoutes.schoolSetup) {
        return AppRoutes.schoolSetup;
      }

      // Signed in — the gates and the login screen are no longer reachable.
      if (location == AppRoutes.splash ||
          location == AppRoutes.login ||
          AppRoutes.gates.contains(location)) {
        return AppRoutes.dashboard;
      }
      return null;
  }
}

/// Bridges Riverpod auth state to `GoRouter.refreshListenable`.
///
/// `ref.listen` fires on every auth transition and notifies the router, which
/// re-runs [_redirect] without rebuilding the route table.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _authSubscription = ref.listen<AuthState>(authControllerProvider, (
      AuthState? previous,
      AuthState next,
    ) {
      if (previous?.status != next.status) notifyListeners();
    });
    // The server gate sits outside auth, so a server change must re-run the
    // redirect too — otherwise connecting a server would leave the user on the
    // connect screen until something else happened to trigger navigation.
    _serverSubscription = ref.listen<ServerConfig?>(serverControllerProvider, (
      ServerConfig? previous,
      ServerConfig? next,
    ) {
      if (previous?.baseUrl != next?.baseUrl) notifyListeners();
    });
    // The first-run gate is the third thing that decides where someone is
    // allowed to be, and like the other two it changes without any navigation
    // happening. Finishing or skipping onboarding only flips a preference —
    // if nothing re-runs the redirect, the buttons do nothing at all and the
    // app is unusable on a fresh install. This listener is what makes them
    // work.
    _welcomeSubscription = ref.listen<bool>(welcomeSeenProvider, (
      bool? previous,
      bool next,
    ) {
      if (previous != next) notifyListeners();
    });
  }

  late final ProviderSubscription<AuthState> _authSubscription;
  late final ProviderSubscription<ServerConfig?> _serverSubscription;
  late final ProviderSubscription<bool> _welcomeSubscription;

  @override
  void dispose() {
    _authSubscription.close();
    _serverSubscription.close();
    _welcomeSubscription.close();
    super.dispose();
  }
}
