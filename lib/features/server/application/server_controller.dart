import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/config/server_config.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/storage/preferences_store.dart';

/// Owns which DRAIS server this installation talks to.
///
/// Resolution order, highest first:
///
/// 1. **A server the user chose**, stored on the device.
/// 2. **The build-time default** (`DRAIS_API_BASE_URL`), which a production
///    release normally sets to the hosted deployment so nobody is ever asked.
/// 3. **Nothing** — the app still opens and renders; it asks when data is
///    first needed.
///
/// There is no fourth step. Guessing an address is what previously pointed
/// builds at a developer's machine.
class ServerController extends StateNotifier<ServerConfig?> {
  /// Creates the controller and resolves the current server immediately.
  ///
  /// Resolution is synchronous because preferences are already open by the
  /// time this is constructed — so the router never sees a "still deciding"
  /// state and no screen flashes on launch.
  ServerController({
    required PreferencesStore preferences,
    required AppConfig config,
    required AppLogger logger,
  }) : _prefs = preferences,
       _config = config,
       _logger = logger.child('Server'),
       super(null) {
    state = _resolve();
  }

  final PreferencesStore _prefs;
  final AppConfig _config;
  final AppLogger _logger;

  /// Whether a server is known, so data screens may be reached.
  bool get isConfigured => state != null;

  /// Whether the user may change the server.
  ///
  /// Always true. Even a build that ships a default may need repointing — a
  /// school moving from hosted DRAIS to its own server should not need a new
  /// APK.
  bool get canChange => true;

  ServerConfig? _resolve() {
    final String? stored = _prefs.serverBaseUrl;
    if (stored != null) {
      final String? normalised = ServerConfig.normalise(stored);
      if (normalised != null) {
        _logger.info(
          'Using the server configured on this device.',
          context: <String, Object?>{'host': Uri.parse(normalised).host},
        );
        return ServerConfig(
          baseUrl: normalised,
          origin: ServerOrigin.userConfigured,
        );
      }
      // Stored value is unusable — drop it rather than failing every request
      // against a malformed address.
      _logger.warn('Stored server address is unreadable; discarding.');
      _prefs.setServerBaseUrl(null);
    }

    final String? fallback = _config.defaultApiBaseUrl;
    if (fallback != null) {
      _logger.info(
        'Using the server this build was configured with.',
        context: <String, Object?>{'host': Uri.parse(fallback).host},
      );
      return ServerConfig(baseUrl: fallback, origin: ServerOrigin.buildDefault);
    }

    _logger.info('No server configured — the app will ask.');
    return null;
  }

  /// Records [rawUrl] as this device's server.
  ///
  /// The caller is expected to have probed the address first — see
  /// `ServerProbe`. This method stores a decision; it does not make one.
  ///
  /// Returns false when the address cannot be normalised, which should not
  /// happen if validation ran.
  Future<bool> setServer(String rawUrl) async {
    final String? normalised = ServerConfig.normalise(rawUrl);
    if (normalised == null) {
      _logger.warn('Refused an unusable server address.');
      return false;
    }

    await _prefs.setServerBaseUrl(normalised);
    state = ServerConfig(
      baseUrl: normalised,
      origin: ServerOrigin.userConfigured,
    );
    _logger.info(
      'Server set.',
      context: <String, Object?>{'host': Uri.parse(normalised).host},
    );
    return true;
  }

  /// Forgets the device's server and falls back to the build default, if any.
  ///
  /// **The caller must sign the user out first.** A session cookie is issued by
  /// one server and meaningless to another; carrying it across would produce a
  /// confusing stream of 401s rather than a clean re-login.
  Future<void> clearServer() async {
    await _prefs.setServerBaseUrl(null);
    state = _resolve();
    _logger.info('Server cleared.');
  }
}
