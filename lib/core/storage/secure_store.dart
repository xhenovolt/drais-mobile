import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:drais/core/logging/app_logger.dart';

/// Credential-grade key/value storage backed by the platform keystore.
///
/// Android uses the AES-encrypted `EncryptedSharedPreferences`; iOS uses the
/// Keychain with `first_unlock_this_device`, so a background refresh after a
/// reboot can still read the session while the data stays off backups and off
/// other devices.
///
/// Only two things belong here: the session cookie jar and the cached identity
/// of the last signed-in user. Everything else goes to [PreferencesStore].
class SecureStore {
  /// Creates a secure store.
  SecureStore({required AppLogger logger, FlutterSecureStorage? storage})
    : _logger = logger.child('SecureStore'),
      _storage =
          storage ??
          const FlutterSecureStorage(
            // v10 removed the EncryptedSharedPreferences option: Google
            // deprecated Jetpack Security, and the plugin now applies its
            // own ciphers, migrating existing entries on first access.
            // Android storage remains encrypted at rest.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;
  final AppLogger _logger;

  /// Reads [key], or null when absent.
  ///
  /// A keystore read can fail outright — a restored backup on Android leaves
  /// entries that cannot be decrypted with the new device key. That must not
  /// crash the app at boot, so a read error is treated as "absent" and logged;
  /// the user simply signs in again.
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object catch (e, s) {
      _logger.warn(
        'Secure read failed; treating as absent.',
        context: <String, Object?>{'key': key, 'reason': e.runtimeType},
      );
      _logger.debug(
        'Secure read detail',
        context: <String, Object?>{'trace': s},
      );
      await delete(key);
      return null;
    }
  }

  /// Writes [value] at [key]. A null [value] deletes the entry.
  Future<void> write(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } on Object catch (e, s) {
      // A failed credential write is not silent: the user would appear signed
      // in and be signed out on next launch with no explanation.
      _logger.error(
        'Secure write failed.',
        error: e,
        stackTrace: s,
        context: <String, Object?>{'key': key},
      );
      rethrow;
    }
  }

  /// Deletes [key], ignoring absence.
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Object catch (e) {
      _logger.warn(
        'Secure delete failed.',
        context: <String, Object?>{'key': key, 'reason': e.runtimeType},
      );
    }
  }

  /// Deletes every DRAIS secure entry.
  ///
  /// Called on sign-out and on an unrecoverable session error. Deliberately
  /// wipes the whole namespace rather than named keys — a key added later and
  /// forgotten here would survive sign-out, which is exactly the bug that
  /// leaves one user's session visible to the next.
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
      _logger.info('Secure storage cleared.');
    } on Object catch (e, s) {
      _logger.error('Secure clear failed.', error: e, stackTrace: s);
    }
  }
}
