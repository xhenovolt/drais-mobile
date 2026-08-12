import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/auth/application/auth_state.dart';

/// Forced password change, for accounts with `users.must_change_password`.
///
/// The web app enforces this through the `drais_force_reset` cookie and a
/// middleware redirect. Mobile enforces the same gate in the router, and this
/// screen is the only way past it — matching the platform's behaviour rather
/// than inventing a mobile-specific escape.
///
/// The password policy is the server's. The two checks below are UX only:
/// catching an obvious mistake before a round trip. Every rule the backend
/// applies still applies, and its rejection is displayed verbatim.
class ChangePasswordPage extends ConsumerStatefulWidget {
  /// Creates the change-password page.
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _busy = false;
  Failure? _failure;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _failure = null;
    });

    final Result<void> result = await ref
        .read(authControllerProvider.notifier)
        .changePassword(
          currentPassword: _current.text,
          newPassword: _next.text,
        );

    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        // The controller reloads the identity, which clears
        // `mustChangePassword` and lets the router move on. Nothing to push.
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password changed.')));
      case Err<void>(:final Failure failure):
        setState(() => _failure = failure);
    }

    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthState auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Change your password'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy
                ? null
                : () => ref.read(authControllerProvider.notifier).logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      auth.requiresPasswordChange
                          ? 'Your administrator requires you to set a new '
                                'password before continuing.'
                          : 'Choose a new password for your DRAIS account.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),

                    if (_failure != null) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _failure!.message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _current,
                      decoration: const InputDecoration(
                        labelText: 'Current password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                      validator: (String? v) => (v == null || v.isEmpty)
                          ? 'Enter your current password'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _next,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                      validator: _validateNewPassword,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _confirm,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                        prefixIcon: Icon(Icons.check_circle_outline),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      enabled: !_busy,
                      validator: (String? v) =>
                          v != _next.text ? 'Passwords do not match' : null,
                      onFieldSubmitted: (String _) => _submit(),
                    ),
                    const SizedBox(height: 24),

                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Change password'),
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

  /// Minimum viable checks only — the server owns the real policy.
  String? _validateNewPassword(String? value) {
    final String password = value ?? '';
    if (password.isEmpty) return 'Enter a new password';
    if (password.length < 8) {
      return 'Use at least 8 characters';
    }
    if (password == _current.text) {
      return 'Choose a password you have not used before';
    }
    return null;
  }
}
