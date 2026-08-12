import 'package:shared_preferences/shared_preferences.dart';

import 'package:drais/core/constants/storage_keys.dart';
import 'package:drais/core/logging/app_logger.dart';

/// Non-sensitive device preferences.
///
/// `SharedPreferences` is plaintext on disk and readable by anyone with the
/// device or a backup. Nothing credential-shaped goes here — see
/// [SecureStore]. The compile-time separation is enforced by keeping the two
/// key namespaces in different classes in
/// `lib/core/constants/storage_keys.dart`.
class PreferencesStore {
  /// Creates a preferences store over an already-initialised backing instance.
  PreferencesStore({
    required SharedPreferences preferences,
    required AppLogger logger,
  }) : _prefs = preferences,
       _logger = logger.child('Preferences');

  /// Opens the platform preference store. Called once during bootstrap.
  static Future<PreferencesStore> open(AppLogger logger) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return PreferencesStore(preferences: prefs, logger: logger);
  }

  final SharedPreferences _prefs;
  final AppLogger _logger;

  /// The email last used on the login form, so a returning user only types a
  /// password. An email is not a credential; a password never lands here.
  String? get rememberedEmail =>
      _prefs.getString(PreferenceKeys.rememberedEmail);

  /// Stores or clears [rememberedEmail].
  Future<void> setRememberedEmail(String? email) => _write(
    PreferenceKeys.rememberedEmail,
    email?.trim().isEmpty ?? true ? null : email!.trim(),
  );

  /// UI locale code (`en` | `ar`), or null to follow the device.
  String? get locale => _prefs.getString(PreferenceKeys.locale);

  /// Sets the UI locale override.
  Future<void> setLocale(String? code) => _write(PreferenceKeys.locale, code);

  /// Theme mode (`system` | `light` | `dark`).
  String get themeMode =>
      _prefs.getString(PreferenceKeys.themeMode) ?? 'system';

  /// Sets the theme mode.
  Future<void> setThemeMode(String mode) =>
      _write(PreferenceKeys.themeMode, mode);

  /// Version string recorded on the last successful launch, used to detect an
  /// upgrade and run one-off migrations.
  String? get lastRunVersion => _prefs.getString(PreferenceKeys.lastRunVersion);

  /// Records the current version as successfully launched.
  Future<void> setLastRunVersion(String version) =>
      _write(PreferenceKeys.lastRunVersion, version);

  /// When `/api/auth/me` last succeeded.
  DateTime? get lastSessionCheckAt {
    final String? raw = _prefs.getString(PreferenceKeys.lastSessionCheckAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Records a successful session check.
  Future<void> setLastSessionCheckAt(DateTime at) =>
      _write(PreferenceKeys.lastSessionCheckAt, at.toUtc().toIso8601String());

  /// Serialised appearance settings, or null when never customised.
  String? get appearance => _prefs.getString(PreferenceKeys.appearance);

  /// Stores appearance settings.
  Future<void> setAppearance(String json) =>
      _write(PreferenceKeys.appearance, json);

  /// Whether setup was skipped on this device.
  bool get setupSkipped => _prefs.getBool(PreferenceKeys.setupSkipped) ?? false;

  /// Records that setup was skipped.
  Future<void> setSetupSkipped() async {
    try {
      await _prefs.setBool(PreferenceKeys.setupSkipped, true);
    } on Object catch (e) {
      _logger.warn(
        'Could not record the setup skip.',
        context: <String, Object?>{'reason': e.runtimeType},
      );
    }
  }

  /// Whether the welcome screen has already been accepted on this device.
  bool get welcomeSeen => _prefs.getBool(PreferenceKeys.welcomeSeen) ?? false;

  /// Records that the welcome screen has been accepted. One-way: there is no
  /// path in the UI that un-sets it, because there is no reason to see it twice.
  Future<void> setWelcomeSeen() async {
    try {
      await _prefs.setBool(PreferenceKeys.welcomeSeen, true);
    } on Object catch (e) {
      _logger.warn(
        'Could not record that the welcome was seen; it may show again.',
        context: <String, Object?>{'reason': e.runtimeType},
      );
    }
  }

  /// The DRAIS server this device is connected to, or null if never set.
  String? get serverBaseUrl => _prefs.getString(PreferenceKeys.serverBaseUrl);

  /// Stores or clears the device's server address.
  Future<void> setServerBaseUrl(String? url) =>
      _write(PreferenceKeys.serverBaseUrl, url);

  /// Clears preferences that describe *this user*, keeping device-level ones
  /// such as theme and locale.
  ///
  /// Sign-out must not reset the interface — a user signing out of a shared
  /// bursar's tablet should not flip it back from Arabic to English.
  Future<void> clearUserScoped() async {
    await _write(PreferenceKeys.rememberedEmail, null);
    await _write(PreferenceKeys.lastSessionCheckAt, null);
    _logger.info('User-scoped preferences cleared.');
  }

  Future<void> _write(String key, String? value) async {
    try {
      if (value == null) {
        await _prefs.remove(key);
      } else {
        await _prefs.setString(key, value);
      }
    } on Object catch (e, s) {
      // A preference is never load-bearing, so a write failure is logged and
      // swallowed rather than propagated into a user-visible error.
      _logger.warn(
        'Preference write failed.',
        context: <String, Object?>{'key': key, 'reason': e.runtimeType},
      );
      _logger.debug(
        'Preference write trace',
        context: <String, Object?>{'trace': s},
      );
    }
  }
}
