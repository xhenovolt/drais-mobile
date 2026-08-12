import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/config/server_config.dart';
import 'package:drais/core/constants/app_version.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/features/server/data/server_probe.dart';

/// Asks which DRAIS server this device should use.
///
/// Shown only when no server is known — that is, a build with no default and
/// no stored choice. A production release that ships a default never reaches
/// this screen unless the user deliberately changes servers.
///
/// ## Why this screen can exist at all
///
/// Every screen in this app is compiled into the binary, so the app opens,
/// renders and navigates with no server whatsoever. That is the structural
/// difference from the Next.js client, whose HTML does not exist until a
/// server produces it. Here the server is needed for *data*, not for pixels —
/// which is precisely what makes "ask the user where the server is" a screen
/// we can show rather than a chicken-and-egg problem.
class ConnectServerPage extends ConsumerStatefulWidget {
  /// Creates the connect screen.
  const ConnectServerPage({super.key});

  @override
  ConsumerState<ConnectServerPage> createState() => _ConnectServerPageState();
}

class _ConnectServerPageState extends ConsumerState<ConnectServerPage> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _probing = false;
  ProbeResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final String? normalised = ServerConfig.normalise(_controller.text);
    if (normalised == null) return;

    setState(() {
      _probing = true;
      _result = null;
    });

    // Prove the address is a DRAIS server before storing it. Saving an
    // unverified address means every later failure looks like a broken app
    // rather than a wrong address.
    final ProbeResult result = await ref
        .read(serverProbeProvider)
        .probe(normalised);

    if (!mounted) return;
    setState(() {
      _probing = false;
      _result = result;
    });

    if (!result.isUsable) return;

    await ref.read(serverControllerProvider.notifier).setServer(normalised);
    // The router is watching; it moves to the login screen on its own.
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppConfig config = ref.watch(appConfigProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Icon(
                      Icons.dns_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Connect to DRAIS',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the DRAIS address for your school. Your '
                      'administrator can give you this.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    TextFormField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        labelText: 'DRAIS address',
                        hintText: 'drais.pro',
                        prefixIcon: Icon(Icons.link),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      autocorrect: false,
                      enableSuggestions: false,
                      enabled: !_probing,
                      validator: (String? value) =>
                          ServerConfig.validateCandidate(
                            value ?? '',
                            config.environment,
                          ),
                      onFieldSubmitted: (String _) => _connect(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Two kinds of address work: your school\'s DRAIS on the '
                      'internet (for example drais.pro), or a DRAIS server '
                      'running on your school network (for example '
                      '192.168.1.50:3210).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_result != null) ...<Widget>[
                      _ProbeFeedback(
                        result: _result!,
                        showDetail: config.environment.allowsDiagnostics,
                      ),
                      const SizedBox(height: 16),
                    ],

                    FilledButton(
                      onPressed: _probing ? null : _connect,
                      child: _probing
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Connect'),
                    ),

                    const SizedBox(height: 32),
                    Text(
                      'DRAIS ${AppVersion.fullVersion}'
                      '${config.environment.isProduction ? '' : ' · ${config.environment.label}'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports what the probe found, distinguishing the three outcomes that need
/// different actions from the user.
class _ProbeFeedback extends StatelessWidget {
  const _ProbeFeedback({required this.result, required this.showDetail});

  final ProbeResult result;
  final bool showDetail;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Usable but degraded (server up, database down) is deliberately its own
    // state: connecting will succeed and signing in will not, and the user
    // needs to know that is not their password.
    final bool warn = result.isUsable && result.problem != null;
    final bool good = result.isUsable && result.problem == null;

    final Color background = good
        ? theme.colorScheme.primaryContainer
        : warn
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.errorContainer;
    final Color foreground = good
        ? theme.colorScheme.onPrimaryContainer
        : warn
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onErrorContainer;

    final String message = good
        ? 'DRAIS server found. Connecting…'
        : result.problem ?? 'Could not use that address.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                good
                    ? Icons.check_circle_outline
                    : warn
                    ? Icons.warning_amber_outlined
                    : Icons.error_outline,
                size: 20,
                color: foreground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
          if (showDetail && result.technicalDetail != null) ...<Widget>[
            const SizedBox(height: 8),
            SelectableText(
              result.technicalDetail!,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
