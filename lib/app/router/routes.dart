/// Every route in DRAIS Mobile, named once.
///
/// Paths mirror the LongTerm web routes (`/login`, `/dashboard`, `/profile`,
/// `/attendance`, …) so that a deep link works the same on both surfaces and
/// so a URL in a support ticket means one thing across the platform.
///
/// Route names are used for navigation; paths are used for deep links.
abstract final class AppRoutes {
  // ── Unauthenticated ────────────────────────────────────────────────────

  /// Session restoration screen, shown while `/api/auth/me` is checked.
  static const String splash = '/';

  /// Route name for [splash].
  static const String splashName = 'splash';

  /// One-time welcome, shown on a fresh installation only.
  static const String welcome = '/welcome';

  /// Route name for [welcome].
  static const String welcomeName = 'welcome';

  /// Registers a school that has never used DRAIS.
  ///
  /// The entry point for a school with no account and therefore no
  /// administrator to issue credentials — without it, the app is a dead end
  /// for exactly the people it needs to reach.
  static const String registerSchool = '/register-school';

  /// Route name for [registerSchool].
  static const String registerSchoolName = 'registerSchool';

  /// Minimum school configuration — year, term, classes. Skippable.
  static const String schoolSetup = '/school-setup';

  /// Route name for [schoolSetup].
  static const String schoolSetupName = 'schoolSetup';

  /// Introductory slides, shown to first-time users after [welcome].
  static const String onboarding = '/onboarding';

  /// Route name for [onboarding].
  static const String onboardingName = 'onboarding';

  /// Server selection, shown when no DRAIS server is configured.
  ///
  /// Outside the web app's route space by nature: the web client is *served
  /// by* its server, so it can never need to ask where that server is.
  static const String connect = '/connect';

  /// Route name for [connect].
  static const String connectName = 'connect';

  /// Sign-in screen. Mirrors the web `/login`.
  static const String login = '/login';

  /// Route name for [login].
  static const String loginName = 'login';

  // ── Gates: authenticated, but not yet admitted ─────────────────────────

  /// Forced password change, for `users.must_change_password`.
  /// The web app redirects here via the `drais_force_reset` cookie.
  static const String changePassword = '/change-password';

  /// Route name for [changePassword].
  static const String changePasswordName = 'changePassword';

  /// Shown when the school's subscription has lapsed or the tenant is
  /// suspended. Explains the situation instead of dropping the user at login,
  /// where signing in again would fail identically and explain nothing.
  static const String accessBlocked = '/access-blocked';

  /// Route name for [accessBlocked].
  static const String accessBlockedName = 'accessBlocked';

  // ── Authenticated ──────────────────────────────────────────────────────

  /// Home — today's attendance. The first tab.
  static const String home = '/home';

  /// Route name for [home].
  static const String homeName = 'home';

  /// Kept so existing links and the router's fallbacks still resolve.
  static const String dashboard = home;

  /// Route name for [dashboard].
  static const String dashboardName = homeName;

  /// Time health — device clocks, drift and corrections. Third tab.
  ///
  /// Named for what it answers rather than for the hardware: the question is
  /// whether the recorded times can be trusted, and a drifting clock is the
  /// commonest reason they cannot.
  static const String timeHealth = '/time-health';

  /// Route name for [timeHealth].
  static const String timeHealthName = 'timeHealth';

  /// Kept so older links resolve.
  static const String devices = timeHealth;

  /// Route name for [devices].
  static const String devicesName = timeHealthName;

  /// Learners — who is enrolled, and their attendance. Fourth tab.
  static const String students = '/students';

  /// Route name for [students].
  static const String studentsName = 'students';

  /// One learner. Mirrors the web `/students/:id`.
  static const String studentDetail = '/students/:id';

  /// Route name for [studentDetail].
  static const String studentDetailName = 'studentDetail';

  /// Builds a path to one learner.
  static String studentDetailPath(int id) => '/students/$id';

  /// Appearance settings — accent, corners, density, wallpaper.
  static const String appearance = '/appearance';

  /// Route name for [appearance].
  static const String appearanceName = 'appearance';

  /// About — version, data mode, coverage, licences.
  static const String about = '/about';

  /// Route name for [about].
  static const String aboutName = 'about';

  /// The attendance log — who came and when. Mirrors the web `/attendance`.
  static const String attendanceLog = '/attendance';

  /// Route name for [attendanceLog].
  static const String attendanceLogName = 'attendanceLog';

  /// Attendance over time. Mirrors the web `/attendance/trends`.
  static const String attendanceTrends = '/attendance/trends';

  /// Route name for [attendanceTrends].
  static const String attendanceTrendsName = 'attendanceTrends';

  /// Punches with no person attached. Mirrors `/attendance/identity-matching`.
  static const String unmatchedPunches = '/attendance/unmatched';

  /// Route name for [unmatchedPunches].
  static const String unmatchedPunchesName = 'unmatchedPunches';

  /// The signed-in user's profile. Mirrors the web `/profile`.
  static const String profile = '/profile';

  /// Route name for [profile].
  static const String profileName = 'profile';

  /// Build, environment and connectivity diagnostics. Hidden in production.
  static const String diagnostics = '/diagnostics';

  /// Route name for [diagnostics].
  static const String diagnosticsName = 'diagnostics';

  /// Routes reachable without a session.
  static const Set<String> public = <String>{
    splash,
    login,
    connect,
    welcome,
    onboarding,
    registerSchool,
  };

  /// The one-time first-run flow: welcome, then the slides.
  static const Set<String> firstRun = <String>{welcome, onboarding};

  /// Routes that are part of an authentication gate rather than the app
  /// proper. A user in a blocked state may reach these and nothing else.
  static const Set<String> gates = <String>{changePassword, accessBlocked};
}
