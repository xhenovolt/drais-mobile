import 'package:flutter/material.dart';

import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/app/theme/appearance.dart';

/// The DRAIS visual identity for mobile.
///
/// ## Built from LongTerm's tokens, not from a seed
///
/// An earlier version generated a Material 3 scheme from one brand colour.
/// That produced a coherent palette that was **not DRAIS's palette** — close
/// enough to look deliberate, different enough that the app felt like another
/// product.
///
/// This version maps [DraisColors] onto `ColorScheme` explicitly. Every value
/// traces to a CSS custom property in `src/app/globals.css`. Where Material
/// wants a role the web has no token for (`surfaceContainerHighest`, say), it
/// is derived from the nearest DRAIS token rather than invented.
///
/// The radius is 8dp, matching `--radius: 0.5rem`. It was 12dp, which is why
/// the cards looked rounder than the web's.
abstract final class AppTheme {
  /// Default corner radius, from `--radius: 0.5rem`. Overridden by
  /// [AppearanceSettings.cornerStyle].
  static const double radius = 8;

  /// Standard page padding.
  static const EdgeInsets pagePadding = EdgeInsets.all(16);

  /// Builds a theme for [brightness] under the user's chosen [settings].
  ///
  /// The DRAIS palette stays the source of truth for surfaces, borders and
  /// status colours; the user chooses the accent, corner treatment and density
  /// on top of it. Letting someone repaint the *surfaces* would break the
  /// contrast the palette was checked for, so those stay fixed.
  static ThemeData from(AppearanceSettings settings, Brightness brightness) =>
      brightness == Brightness.dark ? dark(settings) : light(settings);

  /// The light theme.
  static ThemeData light([
    AppearanceSettings settings = const AppearanceSettings(),
  ]) => _build(
    settings: settings,
    brightness: Brightness.light,
    background: DraisColors.background,
    foreground: DraisColors.foreground,
    card: DraisColors.card,
    cardForeground: DraisColors.cardForeground,
    muted: DraisColors.muted,
    mutedForeground: DraisColors.mutedForeground,
    border: DraisColors.border,
    primary: settings.accent.light,
    secondary: DraisColors.secondary,
    accent: DraisColors.accent,
    danger: DraisColors.danger,
    onPrimary: Colors.white,
  );

  /// The dark theme.
  ///
  /// Not an afterthought: DRAIS is used in halls and offices with poor
  /// lighting, and on the OLED handsets most staff carry.
  static ThemeData dark([
    AppearanceSettings settings = const AppearanceSettings(),
  ]) => _build(
    settings: settings,
    brightness: Brightness.dark,
    background: DraisColors.darkBackground,
    foreground: DraisColors.darkForeground,
    card: DraisColors.darkCard,
    cardForeground: DraisColors.darkCardForeground,
    muted: DraisColors.darkMuted,
    mutedForeground: DraisColors.darkMutedForeground,
    border: DraisColors.darkBorder,
    primary: settings.accent.dark,
    secondary: DraisColors.darkSecondary,
    accent: DraisColors.darkAccent,
    danger: DraisColors.darkDanger,
    // The web uses near-black on its lighter dark-mode blue.
    onPrimary: DraisColors.darkBackground,
  );

  static ThemeData _build({
    required AppearanceSettings settings,
    required Brightness brightness,
    required Color background,
    required Color foreground,
    required Color card,
    required Color cardForeground,
    required Color muted,
    required Color mutedForeground,
    required Color border,
    required Color primary,
    required Color secondary,
    required Color accent,
    required Color danger,
    required Color onPrimary,
  }) {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primary.withValues(alpha: 0.12),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: secondary.withValues(alpha: 0.12),
      onSecondaryContainer: secondary,
      tertiary: accent,
      onTertiary: Colors.white,
      tertiaryContainer: accent.withValues(alpha: 0.12),
      onTertiaryContainer: accent,
      error: danger,
      onError: Colors.white,
      errorContainer: danger.withValues(alpha: 0.12),
      onErrorContainer: danger,
      surface: background,
      onSurface: foreground,
      // Material's "variant" roles carry secondary text and recessed fills;
      // DRAIS expresses both through --muted.
      onSurfaceVariant: mutedForeground,
      surfaceContainerLowest: background,
      surfaceContainerLow: card,
      surfaceContainer: muted,
      surfaceContainerHigh: muted,
      surfaceContainerHighest: muted,
      outline: border,
      outlineVariant: border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: foreground,
      onInverseSurface: background,
      inversePrimary: primary,
    );

    // One radius drives buttons, fields and chips; cards use a capped value so
    // the "pill" setting does not turn surfaces into lozenges.
    final BorderRadius corner = BorderRadius.circular(
      settings.cornerStyle.radius,
    );
    final BorderRadius cardCorner = BorderRadius.circular(
      settings.cornerStyle.cardRadius,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: settings.density.visualDensity,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // A hairline instead of a shadow — the web header is separated by a
        // border, not elevation.
        shape: Border(bottom: BorderSide(color: border)),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: cardCorner,
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: corner,
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: corner,
          borderSide: BorderSide(color: border),
        ),
        // --ring is the focus colour on the web.
        focusedBorder: OutlineInputBorder(
          borderRadius: corner,
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: corner,
          borderSide: BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: corner,
          borderSide: BorderSide(color: danger, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: mutedForeground),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          // 48dp is the accessibility floor; these screens are used one-handed,
          // standing, often in a hurry.
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: corner),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: corner),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: muted,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(color: foreground, fontSize: 12),
      ),

      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),

      listTileTheme: ListTileThemeData(
        iconColor: mutedForeground,
        textColor: foreground,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: corner),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: cardCorner),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    );
  }

  /// The DRAIS splash/welcome gradient.
  static LinearGradient brandGradient({required bool isDark}) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: isDark
        ? const <Color>[
            DraisColors.darkGradientFrom,
            DraisColors.darkGradientTo,
          ]
        : const <Color>[DraisColors.gradientFrom, DraisColors.gradientTo],
  );
}
