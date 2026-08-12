import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/navigation/drais_modules.dart';
import 'package:drais/core/constants/app_version.dart';
import 'package:drais/app/router/routes.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';
import 'package:drais/features/server/application/switch_server.dart';
import 'package:drais/shared/widgets/drais_bottom_nav.dart';

/// A destination in the bottom navigation.
class ShellDestination {
  /// Creates a destination.
  const ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.route,
  });

  /// Label under the icon. One word wherever possible — two wraps on a small
  /// phone and the bar loses its rhythm.
  final String label;

  /// Icon when unselected.
  final IconData icon;

  /// Icon when selected. Filled, so the active tab reads without relying on
  /// colour alone.
  final IconData selectedIcon;

  /// The branch route.
  final String route;
}

/// The persistent frame around the signed-in app.
///
/// ## Why a shell rather than pushed routes
///
/// Everything used to be a `push` onto one stack: you tapped into attendance
/// and the only way back was the system back button. Nothing on screen said
/// where you were or what else existed.
///
/// This wraps the signed-in area in a `StatefulShellRoute`, which gives each
/// tab **its own navigator**. Scroll position and navigation depth survive a
/// tab switch — go into a punch's detail on Attendance, jump to Today, come
/// back, and you are where you left off. That persistence is most of what
/// makes an app feel native rather than like a website in a frame.
///
/// ## Tabs versus drawer
///
/// The bottom bar carries what a person uses *daily*: today's attendance and
/// the log. The drawer carries what they use occasionally — profile,
/// appearance, diagnostics, sign out. A bottom bar with eight items is a menu
/// pretending to be navigation.
class AppShell extends ConsumerWidget {
  /// Creates the shell around [navigationShell].
  const AppShell({required this.navigationShell, super.key});

  /// The branch navigator supplied by `StatefulShellRoute`.
  final StatefulNavigationShell navigationShell;

  /// The navigable branches, in bar order.
  ///
  /// Chosen because DRAIS is an attendance system: the log, whether the times
  /// can be trusted, and who the learners are. Anything a person touches
  /// weekly rather than daily lives in the drawer instead — a bottom bar with
  /// eight items is a menu wearing navigation's clothes.
  static const List<ShellDestination> destinations = <ShellDestination>[
    ShellDestination(
      label: 'Today',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      route: AppRoutes.home,
    ),
    ShellDestination(
      label: 'Attendance',
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check,
      route: AppRoutes.attendanceLog,
    ),
    ShellDestination(
      label: 'Time health',
      icon: Icons.schedule_outlined,
      selectedIcon: Icons.schedule,
      route: AppRoutes.timeHealth,
    ),
    ShellDestination(
      label: 'Students',
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      route: AppRoutes.students,
    ),
  ];

  /// Index of the trailing "More" button.
  ///
  /// It sits in the bar but is **not** a branch: selecting it opens the drawer
  /// and leaves the current tab where it is. That keeps everything occasional
  /// one predictable tap away without spending a navigation slot on it.
  static int get moreIndex => destinations.length;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      drawer: const DraisDrawer(),
      // The bar floats over the content rather than pushing it up, so the
      // page scrolls beneath it. Screens reserve DraisBottomNav.reservedHeight
      // at the foot of their scroll views so the last row clears it.
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: Builder(
        // Its own Builder so `Scaffold.of` resolves to the shell's Scaffold,
        // which is the one holding the drawer.
        builder: (BuildContext context) => DraisBottomNav(
          selectedIndex: navigationShell.currentIndex,
          items: destinations
              .map(
                (ShellDestination d) => DraisNavItem(
                  label: d.label,
                  icon: d.icon,
                  selectedIcon: d.selectedIcon,
                ),
              )
              .toList(growable: false),
          trailing: const DraisNavItem(
            label: 'More',
            icon: Icons.menu,
            selectedIcon: Icons.menu_open,
          ),
          onSelected: (int index) {
            if (index == moreIndex) {
              Scaffold.of(context).openDrawer();
              return;
            }
            navigationShell.goBranch(
              index,
              // Tapping the tab you are already on pops that branch to its
              // root — the behaviour every native app has, and the fastest
              // way back out of a deep screen.
              initialLocation: index == navigationShell.currentIndex,
            );
          },
        ),
      ),
    );
  }
}

/// The navigation drawer — the full DRAIS module catalogue.
///
/// ## Why it lists things that do not work yet
///
/// The web app has around a hundred destinations across nine sections. Mobile
/// has a fraction of them. Showing only what is built would leave a user
/// wondering whether DRAIS mobile is a different, smaller product — so the
/// catalogue is complete, mirrors the web's grouping and wording, and each
/// entry says honestly where it stands: live, planned for a phase, or
/// deliberately web-only with the reason.
///
/// The drawer is therefore also the roadmap, and it cannot drift from reality
/// the way a separate document would.
class DraisDrawer extends ConsumerWidget {
  /// Creates the drawer.
  const DraisDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AuthUser? user = ref.watch(currentUserProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: <Widget>[
            _DrawerHeader(user: user),

            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  for (final ModuleSection section in DraisModules.sections)
                    _Section(section: section, user: user),

                  const Divider(indent: 16, endIndent: 16),

                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('Change server'),
                    dense: true,
                    onTap: () async {
                      Navigator.of(context).pop();
                      await switchServer(ref);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.logout, color: theme.colorScheme.error),
                    title: Text(
                      'Sign out',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    dense: true,
                    onTap: () async {
                      Navigator.of(context).pop();
                      await ref.read(authControllerProvider.notifier).logout();
                    },
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${DraisModules.liveCount} of '
                          '${DraisModules.totalCount} destinations available on '
                          'mobile. The rest are on the web app or on the way.',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // The version belongs where someone will actually see
                        // it without hunting. "Which version are you on?" is
                        // the first question on every support call, and the
                        // drawer is the one surface every user opens.
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            Navigator.of(context).pop();
                            context.pushNamed(AppRoutes.aboutName);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'DRAIS ${AppVersion.fullVersion}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const <FontFeature>[
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One expandable section of the catalogue.
class _Section extends StatelessWidget {
  const _Section({required this.section, required this.user});

  final ModuleSection section;
  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Hide what this user cannot reach, so the drawer reflects their access
    // rather than the whole catalogue. Presentation only — the server checks
    // every request regardless of what is drawn here.
    final List<ModuleItem> visible = section.items
        .where((ModuleItem i) {
          if (i.superAdminOnly && !(user?.isSuperAdmin ?? false)) return false;
          final String? permission = i.permission;
          if (permission != null && user != null && !user!.can(permission)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    if (visible.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      leading: Icon(section.icon, size: 20),
      title: Text(section.label, style: theme.textTheme.titleSmall),
      subtitle: Text(
        '${section.liveCount} of ${section.items.length} available',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      initiallyExpanded: section.initiallyExpanded,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.only(bottom: 4),
      children: visible
          .map((ModuleItem item) => _Item(item: item))
          .toList(growable: false),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.item});

  final ModuleItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = item.isEnabled;

    final Color foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 32, right: 12),
      leading: Icon(item.icon, size: 18, color: foreground),
      title: Text(
        item.label,
        style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
      ),
      subtitle:
          item.availability == ModuleAvailability.webOnly && item.note != null
          ? Text(
              item.note!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: _Badge(item: item),
      onTap: enabled
          ? () {
              Navigator.of(context).pop();
              context.go(item.route!);
            }
          : null,
    );
  }
}

/// Says where an item stands, in as few characters as possible.
class _Badge extends StatelessWidget {
  const _Badge({required this.item});

  final ModuleItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return switch (item.availability) {
      ModuleAvailability.live => const Icon(Icons.chevron_right, size: 18),
      ModuleAvailability.planned => _Chip(
        label: item.phase == null ? 'Soon' : 'Phase ${item.phase}',
        color: theme.colorScheme.tertiary,
      ),
      ModuleAvailability.webOnly => _Chip(
        label: 'Web',
        color: theme.colorScheme.onSurfaceVariant,
      ),
    };
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 16, 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundImage: user?.avatarUrl == null
                ? null
                : NetworkImage(user!.avatarUrl!),
            child: Text(
              user?.initials ?? '?',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user?.displayName ?? 'DRAIS',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user?.school != null)
                  Text(
                    user!.school!.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
