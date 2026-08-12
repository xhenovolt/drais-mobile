import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/config/server_config.dart';
import 'package:drais/core/constants/app_version.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/core/network/api_response.dart';
import 'package:drais/features/auth/application/auth_state.dart';

/// Build, environment and connectivity diagnostics.
///
/// The counterpart of LongTerm's `/api/health` probe and the Electron shell's
/// diagnostic screen. It answers the three questions that account for most
/// field support calls:
///
/// 1. *Which build and environment is this?*
/// 2. *Can the device actually reach the DRAIS server?*
/// 3. *What does the server say about itself?*
///
/// Reachable only in non-production builds — the header on the login screen
/// links to it. Nothing here is secret (the `/api/health` response masks
/// credentials server-side and reports only whether each variable is *set*),
/// but a production user has no use for it and the surface is worth not
/// shipping.
class DiagnosticsPage extends ConsumerStatefulWidget {
  /// Creates the diagnostics page.
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  bool _probing = false;
  String? _healthResult;
  Failure? _healthFailure;

  Future<void> _probeHealth() async {
    setState(() {
      _probing = true;
      _healthResult = null;
      _healthFailure = null;
    });

    final Result<ApiEnvelope<void>> result = await ref
        .read(authRemoteDataSourceProvider)
        .health();

    if (!mounted) return;

    setState(() {
      _probing = false;
      switch (result) {
        case Ok<ApiEnvelope<void>>(:final ApiEnvelope<void> value):
          _healthResult = value.raw.toString();
        case Err<ApiEnvelope<void>>(:final Failure failure):
          _healthFailure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppConfig config = ref.watch(appConfigProvider);
    final AuthState auth = ref.watch(authControllerProvider);
    final AsyncValue<bool> connectivity = ref.watch(connectivityProvider);
    final ServerConfig? server = ref.watch(serverControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _Section(
            title: 'Build',
            rows: <String, String>{
              'Version': AppVersion.fullVersion,
              'Environment': config.environment.label,
              'Verified against LongTerm': AppVersion.verifiedAgainstLongTerm,
              'User agent': AppVersion.userAgent,
            },
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Backend',
            rows: <String, String>{
              'Server': server?.baseUrl ?? '(not configured)',
              'Server source': server?.origin.name ?? '—',
              'Encrypted': '${server?.isSecure ?? false}',
              'Build default':
                  config.defaultApiBaseUrl ?? '(none — asks on first launch)',
              'Connect timeout': '${config.connectTimeout.inSeconds}s',
              'Receive timeout': '${config.receiveTimeout.inSeconds}s',
              'Send timeout': '${config.sendTimeout.inSeconds}s',
              'Retries': '${config.maxRetries}',
              'Page size': '${config.defaultPageSize}',
              'Max upload':
                  '${(config.maxUploadBytes / 1048576).toStringAsFixed(0)} MB',
            },
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Session',
            rows: <String, String>{
              'Status': auth.status.name,
              'User': auth.user?.email ?? '—',
              'School': auth.user?.school?.name ?? '—',
              'School id': '${auth.user?.schoolId ?? '—'}',
              'Super admin': '${auth.user?.isSuperAdmin ?? false}',
              'Roles':
                  auth.user?.roles
                      .map((dynamic r) => r.name as String)
                      .join(', ') ??
                  '—',
              'Permissions': auth.user?.permissions.hasUniversalGrant ?? false
                  ? '* (universal)'
                  : '${auth.user?.permissions.codes.length ?? 0}',
            },
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Connectivity',
            rows: <String, String>{
              'Radio': switch (connectivity) {
                AsyncData<bool>(:final bool value) =>
                  value ? 'connected' : 'no network',
                AsyncError<bool>() => 'unknown',
                _ => 'checking…',
              },
              'Note':
                  'Radio state is a hint. Only the health probe below '
                  'proves the server is reachable.',
            },
          ),
          const SizedBox(height: 24),

          FilledButton.tonal(
            onPressed: _probing ? null : _probeHealth,
            child: _probing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Probe /api/health'),
          ),

          if (_healthFailure != null) ...<Widget>[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _healthFailure!.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    if (_healthFailure!.technicalDetail != null) ...<Widget>[
                      const SizedBox(height: 8),
                      SelectableText(
                        _healthFailure!.technicalDetail!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          if (_healthResult != null) ...<Widget>[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _healthResult!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            for (final MapEntry<String, String> row in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 140,
                      child: Text(
                        row.key,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        row.value,
                        style: theme.textTheme.bodySmall,
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
