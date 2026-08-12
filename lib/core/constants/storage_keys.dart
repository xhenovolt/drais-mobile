/// Every key written to device storage, in one place.
///
/// Scattered string literals are how storage layers rot: a typo becomes a
/// silently empty read, and nobody can enumerate what the app persists when
/// asked to clear it. Keys are namespaced `drais.<area>.<name>` so that a
/// prefix scan can wipe an area wholesale.
library;

/// Keys for values held in the platform keystore/keychain
/// (`flutter_secure_storage`). These are credential-grade.
abstract final class SecureStorageKeys {
  /// Namespace prefix for every secure entry.
  static const String prefix = 'drais.secure.';

  /// Serialised cookie jar for the school-auth domain — holds
  /// `drais_session`, `drais_school_id` and `drais_role`.
  ///
  /// The session cookie is a bearer credential: anything holding it *is* the
  /// user until it expires. It must never touch `SharedPreferences`, which is
  /// plaintext on disk. See `docs/adr/M0002-cookie-session-parity.md`.
  static const String sessionCookies = '${prefix}session_cookies';

  /// Session token for direct database mode.
  ///
  /// In API mode the session lives in the cookie jar; direct mode has no HTTP
  /// layer, so the token is held here instead. Same `sessions` row, same
  /// bearer-credential status — hence the keystore, not preferences.
  static const String directSessionToken = '${prefix}direct_session_token';

  /// Cached identity of the last signed-in user, used to render the login
  /// screen and splash before the network responds. Contains no credential.
  static const String lastKnownUser = '${prefix}last_known_user';
}

/// Keys for non-sensitive values held in `SharedPreferences`.
abstract final class PreferenceKeys {
  /// Namespace prefix for every preference entry.
  static const String prefix = 'drais.prefs.';

  /// Last email entered on the login form, so a returning user only types a
  /// password. An email address is not a credential.
  static const String rememberedEmail = '${prefix}remembered_email';

  /// UI locale override (`en` | `ar`). LongTerm requires every string to exist
  /// in both — see CONTRIBUTING.md "Localization".
  static const String locale = '${prefix}locale';

  /// Theme mode (`system` | `light` | `dark`).
  static const String themeMode = '${prefix}theme_mode';

  /// Serialised [AppearanceSettings] — accent, corners, density, wallpaper,
  /// text scale. Device-level, so it survives sign-out.
  static const String appearance = '${prefix}appearance';

  /// Version of the app that last completed a successful launch. Used to
  /// detect upgrades and run one-off migrations.
  static const String lastRunVersion = '${prefix}last_run_version';

  /// ISO-8601 timestamp of the most recent successful `/api/auth/me`.
  static const String lastSessionCheckAt = '${prefix}last_session_check_at';

  /// Whether the user chose to skip school setup.
  ///
  /// Only suppresses the *automatic* redirect after registering; the home
  /// banner keeps showing until the school genuinely has a year, a term and
  /// classes. Skipping defers a task, it does not dismiss it.
  static const String setupSkipped = '${prefix}setup_skipped';

  /// Whether the welcome screen has been shown and accepted.
  ///
  /// A device-level fact, not a user-level one — it survives sign-out, because
  /// the second person to use a shared school tablet does not need welcoming
  /// to an app that is already installed and running. Only a reinstall or a
  /// data clear brings it back, which is the same behaviour as WhatsApp.
  static const String welcomeSeen = '${prefix}welcome_seen';

  /// The DRAIS server this device is connected to, chosen by the user.
  ///
  /// Not a credential — a server address is not secret, and keeping it in
  /// preferences means it survives a sign-out. A user signing out of a school
  /// tablet should not have to retype the school's server address to sign back
  /// in; it describes the *device's* deployment, not the person.
  static const String serverBaseUrl = '${prefix}server_base_url';
}

/// Keys for the offline response cache.
abstract final class CacheKeys {
  /// Namespace prefix. Everything under it is disposable: clearing the cache
  /// must never sign a user out or lose unsent work.
  static const String prefix = 'drais.cache.';

  /// Cache key for a GET response, derived from its full request URI.
  static String forRequest(String uri) => '$prefix$uri';
}
