import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/app/navigation/drais_modules.dart';
import 'package:drais/app/router/routes.dart';
import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/core/config/data_mode.dart';
import 'package:drais/core/constants/app_version.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/features/auth/domain/entities/auth_user.dart';
import 'package:drais/features/auth/domain/entities/role.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';
import 'package:go_router/go_router.dart';

/// Everything about this installation, in one place.
///
/// ## Why an app needs this screen
///
/// When a head teacher rings to say "the register is wrong", the first three
/// questions are always the same: which version, which mode, which school. On
/// the web app those are a glance at the footer and a look at the URL. On a
/// phone there is no URL and no footer, so without this screen the answer is
/// "I don't know" — and a support call that starts there rarely ends well.
///
/// So this is a diagnostic surface first and a credits page second. Everything
/// here is copyable in one tap, because the realistic next step is pasting it
/// into WhatsApp.
///
/// It deliberately shows the data mode and the database host but **never** the
/// credentials, and it truncates the session identifier — someone screenshots
/// this screen, and a screenshot travels further than they expect.
class AboutPage extends ConsumerWidget {
  /// Creates the about page.
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AuthUser? user = ref.watch(authControllerProvider).user;
    final DirectDbConfig? direct = ref.watch(directDbConfigProvider);

    return Scaffold(
      appBar: DraisAppBar(
        title: 'About DRAIS',
        subtitle: 'Version ${AppVersion.fullVersion}',
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy diagnostics',
            onPressed: () => _copyDiagnostics(context, user, direct),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: <Widget>[
          const _Hero(),
          const SizedBox(height: 20),
          _Section(
            title: 'This build',
            icon: Icons.tag,
            rows: <_Fact>[
              _Fact('Version', AppVersion.semver),
              _Fact('Build', AppVersion.build.toString()),
              _Fact(
                'Verified against',
                'LongTerm ${AppVersion.verifiedAgainstLongTerm}',
              ),
              _Fact('Flavour', _flavour),
              _Fact('Platform', _platform),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'How this app gets its data',
            icon: Icons.hub_outlined,
            footnote: direct != null
                // The single most valuable sentence on this screen. Someone
                // reporting "the app is offline" needs to know whether the app
                // talks to a website or straight to the database, because the
                // two failures look identical and are fixed differently.
                ? 'DRAIS is talking straight to the cloud database. There is '
                      'no website in between, so drais.pro being down does not '
                      'stop this phone from working.'
                : 'DRAIS is talking to a DRAIS server over HTTPS.',
            rows: <_Fact>[
              _Fact('Mode', direct != null ? 'Direct database' : 'API server'),
              if (direct != null) ...<_Fact>[
                _Fact('Host', direct.host),
                _Fact('Database', direct.database),
                _Fact('Port', direct.port.toString()),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (user != null) ...<Widget>[
            _Section(
              title: 'Signed in',
              icon: Icons.badge_outlined,
              rows: <_Fact>[
                _Fact('Name', user.displayName),
                _Fact('Email', user.email),
                _Fact('School', user.school?.name ?? '—'),
                _Fact('School ID', user.schoolId?.toString() ?? '—'),
                _Fact(
                  'Roles',
                  user.roles.isEmpty
                      ? '—'
                      : user.roles.map((Role r) => r.name).join(', '),
                ),
                _Fact(
                  'Permissions',
                  '${user.permissions.codes.length} granted',
                ),
                if (user.isSuperAdmin) _Fact('Super admin', 'Yes'),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const _ModuleProgress(),
          const SizedBox(height: 12),
          _Section(
            title: 'What DRAIS is',
            icon: Icons.info_outline,
            body:
                'DRAIS records attendance from biometric devices. A device '
                'sends a punch, DRAIS works out who it belongs to, and the '
                "rule engine derives that person's verdict for the day — "
                'present, late, half day, absent. Nobody marks a register by '
                'hand.\n\n'
                'That is why the raw punches are kept forever and the verdicts '
                'are recomputed rather than edited: the punch is the evidence, '
                'the verdict is only ever a conclusion drawn from it.',
          ),
          const SizedBox(height: 12),
          _Links(),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '© ${DateTime.now().year} DRAIS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String get _flavour {
    // `kDebugMode` would do, but asserts are the check that survives every
    // build configuration including profile.
    bool debug = false;
    assert(() {
      debug = true;
      return true;
    }());
    return debug ? 'Debug' : 'Release';
  }

  static String get _platform {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    return Platform.operatingSystem;
  }

  Future<void> _copyDiagnostics(
    BuildContext context,
    AuthUser? user,
    DirectDbConfig? direct,
  ) async {
    // Deliberately excludes the password, the session cookie and anything
    // else that would let the reader of a pasted message act as this user.
    final String text = <String>[
      'DRAIS Mobile ${AppVersion.fullVersion} ($_flavour)',
      'Platform: $_platform ${Platform.operatingSystemVersion}',
      'Verified against LongTerm ${AppVersion.verifiedAgainstLongTerm}',
      'Mode: ${direct != null ? 'direct' : 'api'}',
      if (direct != null) 'Host: ${direct.host}/${direct.database}',
      if (user != null)
        'School: ${user.school?.name ?? '?'} (#${user.schoolId})',
      if (user != null)
        'Roles: ${user.roles.map((Role r) => r.name).join(', ')}',
      'Captured: ${DateTime.now().toIso8601String()}',
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostics copied — paste them to support.'),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            theme.colorScheme.primary,
            Color.lerp(
              theme.colorScheme.primary,
              theme.colorScheme.tertiary,
              0.55,
            )!,
          ],
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.fingerprint, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'DRAIS',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Attendance, recorded — not marked.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How much of the platform has landed on mobile, counted from the catalogue.
///
/// Read straight from [draisModules] rather than hardcoded, so it cannot claim
/// a module works when the catalogue still has it planned.
class _ModuleProgress extends StatelessWidget {
  const _ModuleProgress();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final List<ModuleItem> all = DraisModules.sections
        .expand((ModuleSection s) => s.items)
        .toList(growable: false);
    final int live = all
        .where((ModuleItem i) => i.availability == ModuleAvailability.live)
        .length;
    final int webOnly = all
        .where((ModuleItem i) => i.availability == ModuleAvailability.webOnly)
        .length;
    final int planned = all.length - live - webOnly;
    final double fraction = all.isEmpty ? 0 : live / all.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.donut_large,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text('Coverage', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${(fraction * 100).round()}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _Chip(
                  label: '$live on mobile',
                  color: DraisColors.forAttendanceStatus(
                    'present',
                    isDark: isDark,
                  ),
                ),
                _Chip(
                  label: '$planned planned',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                if (webOnly > 0)
                  _Chip(
                    label: '$webOnly web only',
                    color: DraisColors.forAttendanceStatus(
                      'half_day',
                      isDark: isDark,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Counted live from the module catalogue, which is a direct '
              "mirror of the web app's navigation. A module is only marked "
              '"on mobile" when its screen actually exists here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Fact {
  const _Fact(this.label, this.value);

  final String label;
  final String value;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    this.rows = const <_Fact>[],
    this.body,
    this.footnote,
  });

  final String title;
  final IconData icon;
  final List<_Fact> rows;
  final String? body;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            if (rows.isNotEmpty) const SizedBox(height: 12),
            for (final _Fact fact in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 118,
                      child: Text(
                        fact.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        fact.value,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (body != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                body!,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ],
            if (footnote != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                footnote!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Links extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.monitor_heart_outlined),
          title: const Text('Diagnostics'),
          subtitle: const Text('Connection, session and storage checks'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.diagnosticsName),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Appearance'),
          subtitle: const Text('Accent, corners, density, wallpaper'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.appearanceName),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.article_outlined),
          title: const Text('Open source licences'),
          subtitle: const Text('Packages this app is built on'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'DRAIS',
            applicationVersion: AppVersion.fullVersion,
            applicationLegalese: '© ${DateTime.now().year} DRAIS',
          ),
        ),
      ],
    ),
  );
}
