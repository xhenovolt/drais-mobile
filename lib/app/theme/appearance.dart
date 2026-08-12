import 'package:flutter/material.dart';

import 'package:drais/app/theme/app_colors.dart';

/// A selectable accent, each traceable to a DRAIS token.
///
/// Deliberately a fixed set rather than a colour wheel. A free picker lets a
/// user choose a colour that fails contrast against the surfaces, and DRAIS is
/// read in bright sun and dim staff rooms. Every option here is checked
/// against both themes.
enum DraisAccent {
  /// The DRAIS default — blue-600 / blue-500.
  drais('DRAIS Blue', DraisColors.primary, DraisColors.darkPrimary),

  /// violet-600 / violet-500 — the web's `--secondary`.
  violet('Violet', DraisColors.secondary, DraisColors.darkSecondary),

  /// sky-500 / sky-400 — the web's `--accent`.
  sky('Sky', DraisColors.accent, DraisColors.darkAccent),

  /// green-600 / green-500.
  emerald('Emerald', DraisColors.success, DraisColors.darkSuccess),

  /// amber-600 / amber-500.
  amber('Amber', DraisColors.warning, DraisColors.darkWarning),

  /// A deeper indigo for schools that want distance from the default.
  indigo('Indigo', Color(0xFF4F46E5), Color(0xFF818CF8)),

  /// Rose, for the same reason.
  rose('Rose', Color(0xFFE11D48), Color(0xFFFB7185));

  const DraisAccent(this.label, this.light, this.dark);

  /// Name shown in settings.
  final String label;

  /// Colour on light surfaces.
  final Color light;

  /// Colour on dark surfaces — lighter, so it holds contrast on near-black.
  final Color dark;

  /// The colour for [brightness].
  Color of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// How corners are cut across the whole app.
///
/// Applied to buttons, cards, fields, chips and sheets together. Letting these
/// drift apart is what makes an interface feel assembled rather than designed.
enum DraisCornerStyle {
  /// Square-ish, 4dp. Dense and businesslike.
  sharp('Sharp', 4),

  /// 8dp — matches the web's `--radius: 0.5rem`. The default.
  rounded('Rounded', 8),

  /// 16dp. Softer, more consumer.
  soft('Soft', 16),

  /// Fully rounded ends. Buttons and chips become pills.
  pill('Pill', 999);

  const DraisCornerStyle(this.label, this.radius);

  /// Name shown in settings.
  final String label;

  /// Corner radius in logical pixels.
  final double radius;

  /// Radius for a card. Pills are capped — a fully-rounded *card* is
  /// unreadable, so the pill setting affects controls, not surfaces.
  double get cardRadius => this == DraisCornerStyle.pill ? 20 : radius;
}

/// Interface density.
enum DraisDensity {
  /// Roomy. Easier to hit while standing at a gate.
  comfortable('Comfortable', 0),

  /// Tighter, fits more rows — a bursar scanning a long ledger.
  compact('Compact', -1);

  const DraisDensity(this.label, this.value);

  /// Name shown in settings.
  final String label;

  /// Feeds `VisualDensity`.
  final double value;

  /// The Flutter density.
  VisualDensity get visualDensity =>
      VisualDensity(horizontal: value, vertical: value);
}

/// An optional backdrop behind scaffold content.
///
/// Drawn, not photographic. A photo wallpaper behind dense attendance data
/// costs legibility for decoration; these are low-contrast gradients and
/// patterns that stay out of the way of text.
enum DraisWallpaper {
  /// No backdrop. Flat surface colour.
  none('None'),

  /// A soft vertical wash of the accent, strongest at the top.
  gradient('Gradient'),

  /// Faint diagonal lines.
  weave('Weave'),

  /// A dotted grid, like graph paper.
  grid('Grid'),

  /// Large, very low-opacity accent circles.
  bloom('Bloom');

  const DraisWallpaper(this.label);

  /// Name shown in settings.
  final String label;
}

/// Everything the user can change about how DRAIS looks.
///
/// Immutable and serialisable to a preferences map. Adding a knob means adding
/// a field here, a case in [toMap]/[fromMap], and a control in the appearance
/// screen — nothing else in the app needs to know.
@immutable
class AppearanceSettings {
  /// Creates appearance settings.
  const AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.accent = DraisAccent.drais,
    this.cornerStyle = DraisCornerStyle.rounded,
    this.density = DraisDensity.comfortable,
    this.wallpaper = DraisWallpaper.none,
    this.textScale = 1.0,
  });

  /// Restores from stored values, falling back to defaults for anything
  /// unrecognised — a setting written by a newer build must not break an
  /// older one.
  factory AppearanceSettings.fromMap(Map<String, Object?> map) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) {
      if (name is! String) return fallback;
      for (final T value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    return AppearanceSettings(
      themeMode: pick(ThemeMode.values, map['themeMode'], ThemeMode.system),
      accent: pick(DraisAccent.values, map['accent'], DraisAccent.drais),
      cornerStyle: pick(
        DraisCornerStyle.values,
        map['cornerStyle'],
        DraisCornerStyle.rounded,
      ),
      density: pick(
        DraisDensity.values,
        map['density'],
        DraisDensity.comfortable,
      ),
      wallpaper: pick(
        DraisWallpaper.values,
        map['wallpaper'],
        DraisWallpaper.none,
      ),
      textScale: (map['textScale'] as num?)?.toDouble().clamp(0.85, 1.4) ?? 1.0,
    );
  }

  /// Light, dark, or follow the system.
  final ThemeMode themeMode;

  /// Accent colour.
  final DraisAccent accent;

  /// Corner treatment for controls and surfaces.
  final DraisCornerStyle cornerStyle;

  /// Interface density.
  final DraisDensity density;

  /// Optional backdrop.
  final DraisWallpaper wallpaper;

  /// Text scale, 0.85–1.4.
  ///
  /// Clamped rather than free: beyond this range the attendance rows stop
  /// fitting and the layout breaks in ways a user cannot undo from the screen
  /// they broke it on.
  final double textScale;

  /// Whether these are the shipped defaults.
  bool get isDefault =>
      themeMode == ThemeMode.system &&
      accent == DraisAccent.drais &&
      cornerStyle == DraisCornerStyle.rounded &&
      density == DraisDensity.comfortable &&
      wallpaper == DraisWallpaper.none &&
      textScale == 1.0;

  /// Returns a copy with the given overrides.
  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    DraisAccent? accent,
    DraisCornerStyle? cornerStyle,
    DraisDensity? density,
    DraisWallpaper? wallpaper,
    double? textScale,
  }) => AppearanceSettings(
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    cornerStyle: cornerStyle ?? this.cornerStyle,
    density: density ?? this.density,
    wallpaper: wallpaper ?? this.wallpaper,
    textScale: textScale ?? this.textScale,
  );

  /// Serialises for storage.
  Map<String, Object?> toMap() => <String, Object?>{
    'themeMode': themeMode.name,
    'accent': accent.name,
    'cornerStyle': cornerStyle.name,
    'density': density.name,
    'wallpaper': wallpaper.name,
    'textScale': textScale,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppearanceSettings &&
          other.themeMode == themeMode &&
          other.accent == accent &&
          other.cornerStyle == cornerStyle &&
          other.density == density &&
          other.wallpaper == wallpaper &&
          other.textScale == textScale;

  @override
  int get hashCode => Object.hash(
    themeMode,
    accent,
    cornerStyle,
    density,
    wallpaper,
    textScale,
  );
}
