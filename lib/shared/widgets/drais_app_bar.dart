import 'package:flutter/material.dart';

import 'package:drais/app/theme/app_colors.dart';

/// The DRAIS app bar.
///
/// One app bar for the whole application, from day one. Screens supply a
/// title, an optional subtitle and actions; they do not construct their own
/// `AppBar`, because an interface where each screen invents its own header is
/// how a product starts feeling assembled rather than designed.
///
/// ## What it gives every screen for free
///
/// * A two-line title/subtitle that degrades to one line cleanly. The subtitle
///   is where the *context* goes — which school, which class, which date —
///   and having a fixed place for it means a user always knows where to look.
/// * A hairline bottom border rather than elevation, matching the web header.
/// * An optional accent strip, used to carry status colour into the chrome
///   (attendance uses it while a day is still provisional).
/// * A progress hairline for in-flight work that must not block the screen.
class DraisAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates a DRAIS app bar.
  const DraisAppBar({
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.busy = false,
    this.accentStrip,
    this.bottom,
    super.key,
  });

  /// Primary line. Say what the screen *is*, not what it does.
  final String title;

  /// Secondary line — the context this screen is showing.
  final String? subtitle;

  /// Trailing actions. Keep to three; more belongs in an overflow menu.
  final List<Widget>? actions;

  /// Leading widget. Defaults to the framework's back button.
  final Widget? leading;

  /// Shows an indeterminate hairline under the bar.
  ///
  /// For refreshes that must not take the content away — pulling new
  /// attendance should not blank the list a teacher is reading.
  final bool busy;

  /// A colour strip along the bottom edge, for screen-level status.
  final Color? accentStrip;

  /// Extra chrome below the title — a filter row, a segmented control.
  final PreferredSizeWidget? bottom;

  static const double _barHeight = 60;
  static const double _stripHeight = 3;

  @override
  Size get preferredSize => Size.fromHeight(
    _barHeight +
        (bottom?.preferredSize.height ?? 0) +
        (accentStrip != null ? _stripHeight : 0),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;

    return AppBar(
      toolbarHeight: _barHeight,
      leading: leading,
      titleSpacing: leading == null ? 16 : 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasSubtitle)
            Text(
              subtitle!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: actions,
      bottom: _buildBottom(theme),
    );
  }

  PreferredSizeWidget? _buildBottom(ThemeData theme) {
    final List<Widget> layers = <Widget>[
      ?bottom,
      if (busy)
        LinearProgressIndicator(
          minHeight: 2,
          backgroundColor: Colors.transparent,
          color: theme.colorScheme.primary,
        ),
      if (accentStrip != null)
        Container(height: _stripHeight, color: accentStrip),
    ];

    if (layers.isEmpty) return null;

    return PreferredSize(
      preferredSize: Size.fromHeight(
        (bottom?.preferredSize.height ?? 0) +
            (busy ? 2 : 0) +
            (accentStrip != null ? _stripHeight : 0),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: layers),
    );
  }
}

/// A compact status pill, shaped by the app's corner setting.
///
/// Used for attendance statuses, device states and sync state. Kept here
/// rather than in each feature so that "what a pill looks like" is answered
/// once — which is the whole point of a design system.
class DraisPill extends StatelessWidget {
  /// Creates a pill.
  const DraisPill({
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
    super.key,
  });

  /// Short text. One or two words; a pill is not a sentence.
  final String label;

  /// The status colour. Drives the border, the text and the tint.
  final Color color;

  /// Optional leading icon.
  final IconData? icon;

  /// Solid rather than tinted, for the one status that must dominate.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color foreground = filled ? Colors.white : color;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? 10 : 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        // Always fully rounded: a pill is a pill regardless of the corner
        // setting, which governs cards, fields and buttons.
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: filled ? color : color.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill for an `attendance_records.status` value.
///
/// A widget rather than a factory on [DraisPill] because the colour depends on
/// the active brightness, and a constructor has no `BuildContext` to read it
/// from. Getting that wrong would show light-mode status colours on a dark
/// background — legible enough to ship, wrong enough to look broken.
///
/// Central so the same status never reads differently on two screens.
class AttendanceStatusPill extends StatelessWidget {
  /// Creates a status pill.
  const AttendanceStatusPill(this.status, {this.filled = false, super.key});

  /// The raw `attendance_records.status` value, or null when unmarked.
  final String? status;

  /// Whether to render solid rather than tinted.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final ({String label, IconData icon}) presentation = switch (status) {
      'present' => (label: 'Present', icon: Icons.check_circle_outline),
      'late' => (label: 'Late', icon: Icons.schedule),
      'absent' => (label: 'Absent', icon: Icons.cancel_outlined),
      'half_day' => (label: 'Half day', icon: Icons.contrast),
      'early_leave' => (label: 'Left early', icon: Icons.logout),
      'holiday' => (label: 'Holiday', icon: Icons.beach_access_outlined),
      'weekend' => (label: 'Weekend', icon: Icons.weekend_outlined),
      // Deliberately not "absent": no record means nobody has said anything
      // about this learner today, which is a different claim entirely.
      _ => (label: 'Not marked', icon: Icons.remove_circle_outline),
    };

    return DraisPill(
      label: presentation.label,
      icon: presentation.icon,
      color: DraisColors.forAttendanceStatus(status, isDark: isDark),
      filled: filled,
    );
  }
}
