import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/di/providers.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';
import 'package:drais/features/auth/domain/entities/role.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:drais/shared/widgets/loading_view.dart';

/// The signed-in user: who they are, and what they may do.
///
/// This is where the identity, roles and permission detail moved to when the
/// home screen became attendance-first. It was never wrong information — it
/// was in the wrong place, greeting someone who opened the app to check who
/// had arrived.
class ProfilePage extends ConsumerWidget {
  /// Creates the profile page.
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AuthUser? user = ref.watch(currentUserProvider);

    if (user == null) {
      return const Scaffold(body: LoadingView(label: 'Loading…'));
    }

    final List<String> codes = user.permissions.codes.toList()..sort();

    return Scaffold(
      appBar: DraisAppBar(title: user.displayName, subtitle: user.email),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundImage: user.avatarUrl == null
                        ? null
                        : NetworkImage(user.avatarUrl!),
                    child: Text(
                      user.initials,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          user.displayName,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          user.email,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (user.school != null)
                          Text(
                            user.school!.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Roles', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      if (user.isSuperAdmin)
                        Chip(
                          avatar: const Icon(Icons.verified_user, size: 16),
                          label: const Text('Super admin'),
                          backgroundColor: theme.colorScheme.primaryContainer,
                        ),
                      ...user.roles.map((Role r) => Chip(label: Text(r.name))),
                      if (user.roles.isEmpty && !user.isSuperAdmin)
                        Text(
                          'No roles assigned.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('Permissions', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      Text(
                        user.permissions.hasUniversalGrant
                            ? 'all'
                            : '${codes.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user.permissions.hasUniversalGrant
                        ? 'This account holds the universal grant, so every '
                              'permission check passes.'
                        : 'Granted by the roles above. The server re-checks '
                              'every one of these on each request.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!user.permissions.hasUniversalGrant &&
                      codes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'Show permission codes',
                        style: theme.textTheme.labelLarge,
                      ),
                      children: <Widget>[
                        for (final String code in codes)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.check, size: 16),
                            title: Text(
                              code,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
