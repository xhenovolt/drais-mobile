import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/app/theme/appearance.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/storage/preferences_store.dart';

/// Owns how DRAIS looks, and remembers it.
///
/// ## Device-level, not user-level
///
/// Appearance survives sign-out, like theme and locale. Someone signing out of
/// a shared bursar's tablet should not reset it to defaults for the next
/// person — the setting describes the *device*, not the person holding it.
///
/// Changes apply immediately: the root widget watches this and rebuilds with a
/// new `ThemeData`. There is no "apply" button, because there is nothing to
/// commit — the preview *is* the result.
class AppearanceController extends StateNotifier<AppearanceSettings> {
  /// Creates the controller and restores the stored settings.
  AppearanceController({
    required PreferencesStore preferences,
    required AppLogger logger,
  }) : _prefs = preferences,
       _logger = logger.child('Appearance'),
       super(const AppearanceSettings()) {
    state = _restore();
  }

  final PreferencesStore _prefs;
  final AppLogger _logger;

  AppearanceSettings _restore() {
    final String? raw = _prefs.appearance;
    if (raw == null || raw.isEmpty) return const AppearanceSettings();

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const AppearanceSettings();
      return AppearanceSettings.fromMap(
        decoded.map(
          (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
        ),
      );
    } on Object catch (e) {
      // Corrupt settings must never stop the app drawing — fall back to the
      // defaults and carry on.
      _logger.warn(
        'Stored appearance was unreadable; using defaults.',
        context: <String, Object?>{'reason': e.runtimeType},
      );
      return const AppearanceSettings();
    }
  }

  Future<void> _apply(AppearanceSettings next) async {
    if (next == state) return;
    state = next;
    await _prefs.setAppearance(jsonEncode(next.toMap()));
  }

  /// Sets light, dark or system.
  Future<void> setThemeMode(ThemeMode mode) =>
      _apply(state.copyWith(themeMode: mode));

  /// Sets the accent colour.
  Future<void> setAccent(DraisAccent accent) =>
      _apply(state.copyWith(accent: accent));

  /// Sets the corner treatment for controls and surfaces.
  Future<void> setCornerStyle(DraisCornerStyle style) =>
      _apply(state.copyWith(cornerStyle: style));

  /// Sets interface density.
  Future<void> setDensity(DraisDensity density) =>
      _apply(state.copyWith(density: density));

  /// Sets the backdrop.
  Future<void> setWallpaper(DraisWallpaper wallpaper) =>
      _apply(state.copyWith(wallpaper: wallpaper));

  /// Sets the text scale, clamped to a range the layouts survive.
  Future<void> setTextScale(double scale) =>
      _apply(state.copyWith(textScale: scale.clamp(0.85, 1.4)));

  /// Restores the shipped defaults.
  ///
  /// Worth having as one action: a user who has made the interface unreadable
  /// needs a way back that does not require reading it.
  Future<void> reset() => _apply(const AppearanceSettings());
}
