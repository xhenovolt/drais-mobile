import 'package:flutter/material.dart';

/// The DRAIS palette, transcribed from LongTerm's design tokens.
///
/// ## These are copied values, not chosen ones
///
/// Every colour here comes from `:root` and `html.dark` in
/// `src/app/globals.css`. The comments name the Tailwind shade each one maps
/// to, so a change on the web side can be found and mirrored here rather than
/// guessed at.
///
/// **Do not invent a colour.** A bursar moving between the web app and the
/// phone should not be able to tell that two teams built them. If a shade is
/// needed that does not exist here, it should be added to the web tokens
/// first and copied across — the web app is the source of truth for brand,
/// exactly as the server is for data.
abstract final class DraisColors {
  // ── Light ────────────────────────────────────────────────────────────────

  /// Page background.
  static const Color background = Color(0xFFFFFFFF);

  /// Default text.
  static const Color foreground = Color(0xFF171717);

  /// Card and sheet surfaces.
  static const Color card = Color(0xFFFFFFFF);

  /// Text on cards.
  static const Color cardForeground = Color(0xFF171717);

  /// Recessed surfaces — slate-100.
  static const Color muted = Color(0xFFF1F5F9);

  /// Secondary text — slate-500.
  static const Color mutedForeground = Color(0xFF64748B);

  /// Hairlines and input outlines — slate-200.
  static const Color border = Color(0xFFE2E8F0);

  /// Brand blue — blue-600. The single most recognisable DRAIS colour.
  static const Color primary = Color(0xFF2563EB);

  /// Violet-600, used for secondary emphasis.
  static const Color secondary = Color(0xFF7C3AED);

  /// Sky-500.
  static const Color accent = Color(0xFF0EA5E9);

  /// Red-600. Destructive actions and errors.
  static const Color danger = Color(0xFFDC2626);

  /// Amber-600. Expiring subscriptions, "needs attention".
  static const Color warning = Color(0xFFD97706);

  /// Green-600. Present, paid, confirmed.
  static const Color success = Color(0xFF16A34A);

  /// Sky-600. Neutral information.
  static const Color info = Color(0xFF0284C7);

  /// Splash and header gradient, light.
  static const Color gradientFrom = Color(0xFFF9FAFB);

  /// Splash and header gradient, light.
  static const Color gradientTo = Color(0xFFDBEAFE);

  // ── Dark ─────────────────────────────────────────────────────────────────

  /// Page background, dark.
  static const Color darkBackground = Color(0xFF0A0A0A);

  /// Default text, dark.
  static const Color darkForeground = Color(0xFFEDEDED);

  /// Card surfaces, dark — slate-900.
  static const Color darkCard = Color(0xFF0F172A);

  /// Text on cards, dark — slate-200.
  static const Color darkCardForeground = Color(0xFFE2E8F0);

  /// Recessed surfaces, dark — slate-800.
  static const Color darkMuted = Color(0xFF1E293B);

  /// Secondary text, dark — slate-400.
  static const Color darkMutedForeground = Color(0xFF94A3B8);

  /// Hairlines, dark — slate-800.
  static const Color darkBorder = Color(0xFF1E293B);

  /// Brand blue on dark — blue-500, deliberately a touch lighter so it holds
  /// contrast against near-black. The web tokens carry the same note.
  static const Color darkPrimary = Color(0xFF3B82F6);

  /// Violet-500.
  static const Color darkSecondary = Color(0xFF8B5CF6);

  /// Sky-400.
  static const Color darkAccent = Color(0xFF38BDF8);

  /// Red-500, dark.
  static const Color darkDanger = Color(0xFFEF4444);

  /// Amber-500, dark.
  static const Color darkWarning = Color(0xFFF59E0B);

  /// Green-500, dark.
  static const Color darkSuccess = Color(0xFF22C55E);

  /// Sky-400, dark.
  static const Color darkInfo = Color(0xFF38BDF8);

  /// Splash and header gradient, dark.
  static const Color darkGradientFrom = Color(0xFF0F172A);

  /// Splash and header gradient, dark.
  static const Color darkGradientTo = Color(0xFF172554);

  // ── Attendance status ────────────────────────────────────────────────────

  /// Colour for an `attendance_records.status` value.
  ///
  /// The enum is fixed by the schema — `present`, `late`, `absent`,
  /// `half_day`, `early_leave`, `holiday`, `weekend` — and these map onto the
  /// semantic tokens above rather than introducing new shades. Attendance is
  /// the screen staff look at most, so its colours must read instantly and
  /// mean the same thing they do on the web.
  static Color forAttendanceStatus(String? status, {required bool isDark}) =>
      switch (status) {
        'present' => isDark ? darkSuccess : success,
        'late' => isDark ? darkWarning : warning,
        'absent' => isDark ? darkDanger : danger,
        'half_day' || 'early_leave' => isDark ? darkAccent : accent,
        'holiday' ||
        'weekend' => isDark ? darkMutedForeground : mutedForeground,
        // Not marked. Deliberately grey, never red: an unmarked learner is an
        // absence of information, not an absence.
        _ => isDark ? darkMutedForeground : mutedForeground,
      };
}
