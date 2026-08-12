import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/config/app_config.dart';
import 'package:drais/core/config/server_config.dart';
import 'package:drais/core/constants/app_version.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/features/auth/application/auth_state.dart';

/// The sign-in screen.
///
/// Consumes `POST /api/auth/login` unchanged. No credential handling is
/// reimplemented here: the password is sent as typed and verified server-side
/// with bcrypt, the session is an `HttpOnly` cookie the app merely stores, and
/// the identity comes from `/api/auth/me`. The screen's whole job is to
/// collect two strings and render what the server said.
class LoginPage extends ConsumerStatefulWidget {
  /// Creates the login page.
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _prefillEmail();
  }

  Future<void> _prefillEmail() async {
    final String? email = await ref
        .read(authControllerProvider.notifier)
        .lastUsedEmail();
    if (!mounted || email == null) return;
    _emailController.text = email;
    // A returning user lands on the password field with the keyboard up.
    _passwordFocus.requestFocus();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    await ref
        .read(authControllerProvider.notifier)
        .login(
          email: _emailController.text,
          password: _passwordController.text,
        );
    // Navigation is the router's job — it is watching auth state. Pushing a
    // route here would create a second way into the app that does not consult
    // the gates.
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final AppConfig config = ref.watch(appConfigProvider);
    final Failure? failure = auth.failure;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Icon(
                      Icons.school_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Sign in to DRAIS',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use the same email and password as the DRAIS web app.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    if (failure != null) ...<Widget>[
                      _FailureBanner(failure: failure),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const <String>[AutofillHints.username],
                      enabled: !auth.isBusy,
                      validator: _validateEmail,
                      onFieldSubmitted: (String _) =>
                          _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const <String>[AutofillHints.password],
                      enabled: !auth.isBusy,
                      validator: (String? value) =>
                          (value == null || value.isEmpty)
                          ? 'Enter your password'
                          : null,
                      onFieldSubmitted: (String _) => _submit(),
                    ),
                    const SizedBox(height: 24),

                    FilledButton(
                      onPressed: auth.isBusy ? null : _submit,
                      child: auth.isBusy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),

                    const SizedBox(height: 24),
                    // Password reset is a web-only flow today. Saying so is
                    // better than an inert link or a screen that cannot work.
                    Text(
                      'Forgotten your password? Ask your school administrator '
                      'to reset it, or use the DRAIS web app.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 4),
                    // The way in for a school that has no DRAIS account and
                    // therefore no administrator to issue credentials.
                    Text(
                      'New to DRAIS?',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: auth.isBusy
                          ? null
                          : () => context.push(AppRoutes.registerSchool),
                      child: const Text('Register your school'),
                    ),

                    const SizedBox(height: 16),
                    // Reachable in every environment, deliberately. A user
                    // signed out against the wrong server would otherwise have
                    // no way out except reinstalling the app.
                    const _ConnectedServerFooter(),

                    const SizedBox(height: 16),
                    _EnvironmentFooter(config: config),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Format check only. Whether the account exists is the server's business,
  /// and it deliberately will not say.
  static String? _validateEmail(String? value) {
    final String email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email';
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address';
    }
    return null;
  }
}

/// Renders a sign-in failure with wording matched to its cause.
class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Subscription and account-state problems are not "wrong password", and
    // colouring them the same way sends people to reset a working password.
    final bool isCredentialProblem =
        failure is AuthenticationFailure && !failure.requiresReauthentication;
    final Color background = isCredentialProblem
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.tertiaryContainer;
    final Color foreground = isCredentialProblem
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isCredentialProblem ? Icons.error_outline : Icons.info_outline,
            size: 20,
            color: foreground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              failure.message,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Names the connected server and offers a way to change it.
///
/// The address is shown as a host, not a full URL — it is there so a user can
/// confirm "am I on the school server or the hosted one" at a glance, and so a
/// support call can be answered from a screenshot.
class _ConnectedServerFooter extends ConsumerWidget {
  const _ConnectedServerFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ServerConfig? server = ref.watch(serverControllerProvider);

    if (server == null) return const SizedBox.shrink();

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              server.isSecure ? Icons.lock_outline : Icons.lan_outlined,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                server.displayHost,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: () =>
              ref.read(serverControllerProvider.notifier).clearServer(),
          child: const Text('Change server'),
        ),
      ],
    );
  }
}

/// Shows which backend this build talks to, outside production.
///
/// The commonest support question during a rollout is "why can't I sign in",
/// and the commonest answer is "you installed the staging build". Naming the
/// environment on the login screen settles it in one screenshot.
class _EnvironmentFooter extends ConsumerWidget {
  const _EnvironmentFooter({required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    if (config.environment.isProduction) {
      return Text(
        'DRAIS ${AppVersion.fullVersion}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      );
    }

    return Column(
      children: <Widget>[
        Chip(
          label: Text('${config.environment.label} build'),
          avatar: const Icon(Icons.construction, size: 16),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(height: 8),
        Text(
          ref.watch(serverControllerProvider)?.baseUrl ?? '(no server)',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        TextButton(
          onPressed: () => context.push(AppRoutes.diagnostics),
          child: const Text('Diagnostics'),
        ),
      ],
    );
  }
}
