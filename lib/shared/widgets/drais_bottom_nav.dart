import 'dart:ui';

import 'package:flutter/material.dart';

/// One item in the floating bar.
class DraisNavItem {
  /// Creates a nav item.
  const DraisNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  /// Shown under the icon when inactive, and beside it when active.
  final String label;

  /// Icon when inactive — outlined.
  final IconData icon;

  /// Icon when active — filled, so the selection reads without relying on
  /// colour alone.
  final IconData selectedIcon;
}

/// A floating, pill-shaped bottom navigation bar.
///
/// ## Why not `NavigationBar`
///
/// Material's bar is edge-to-edge and welded to the bottom of the screen. It
/// is correct, and it looks like every Android app from 2021. A bar that
/// floats above the content — inset from the edges, fully rounded, with the
/// page scrolling beneath it — is what reads as current, and it costs a
/// custom widget rather than a compromise in behaviour.
///
/// ## The active pill
///
/// The selected item expands into a filled pill carrying its label; the others
/// stay as bare icons. That gives three simultaneous signals for where you are
/// — shape, fill and text — instead of a colour change alone, which is the
/// thing that fails for a colour-blind user and in bright sunlight.
///
/// The host `Scaffold` must set `extendBody: true` so content flows under it,
/// and screens should pad their scroll views by [reservedHeight] so the last
/// row is not trapped behind the bar.
class DraisBottomNav extends StatelessWidget {
  /// Creates a floating bottom navigation bar.
  const DraisBottomNav({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.trailing,
    super.key,
  });

  /// The navigable items.
  final List<DraisNavItem> items;

  /// Which item is active.
  final int selectedIndex;

  /// Called with the tapped index. Indices beyond [items] belong to
  /// [trailing].
  final ValueChanged<int> onSelected;

  /// An extra item that is an action rather than a destination — "More",
  /// which opens the drawer. Never shows as selected, because tapping it does
  /// not change where you are.
  final DraisNavItem? trailing;

  /// Vertical space a screen should reserve at the bottom of a scroll view.
  static const double reservedHeight = 92;

  static const double _barHeight = 62;
  static const double _radius = 30;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            // The blur is what makes it read as floating *above* content
            // rather than as an opaque strip pasted over it.
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: _barHeight,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer.withValues(
                  alpha: isDark ? 0.82 : 0.92,
                ),
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: isDark ? 0.7 : 1,
                  ),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  for (int i = 0; i < items.length; i++)
                    _NavButton(
                      item: items[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelected(i),
                    ),
                  if (trailing != null)
                    _NavButton(
                      item: trailing!,
                      // Deliberately never selected: it opens a drawer and
                      // leaves the current tab alone, so showing it as active
                      // would misreport where the user is.
                      selected: false,
                      onTap: () => onSelected(items.length),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final DraisNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 14 : 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 21,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              // The label appears only on the active item. Showing all five
              // at once forces every label to shrink to fit a phone, and then
              // none of them is readable.
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: Text(
                          item.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
