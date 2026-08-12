import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/core/di/providers.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/features/auth/application/auth_state.dart';

/// Registers a school that has never used DRAIS.
///
/// ## Why this exists
///
/// Every other route into the app assumes credentials were issued to you by an
/// administrator. For a school with no DRAIS account there is no administrator
/// yet, so that assumption made the app a dead end for exactly the people it
/// most needs to reach.
///
/// One screen provisions a whole tenant: the school on a 30-day trial, a Super
/// Admin role scoped to it, the signer-up holding that role, and a session.
/// They are signed in when it returns.
///
/// ## What it deliberately does not collect
///
/// Address, school type, logo, terms, classes, academic year. Those are
/// configuration, not registration — asking for them here would turn a
/// two-minute sign-up into a form nobody finishes on a phone. The school is
/// created with `setup_complete = false`, and the app says plainly that setup
/// continues on the web.
class RegisterSchoolPage extends ConsumerStatefulWidget {
  /// Creates the registration page.
  const RegisterSchoolPage({super.key});

  @override
  ConsumerState<RegisterSchoolPage> createState() => _RegisterSchoolPageState();
}

class _RegisterSchoolPageState extends ConsumerState<RegisterSchoolPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _school = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _obscure = true;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _school,
      _firstName,
      _lastName,
      _email,
      _phone,
      _password,
      _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    await ref
        .read(authControllerProvider.notifier)
        .registerSchool(
          schoolName: _school.text,
          firstName: _firstName.text,
          lastName: _lastName.text,
          email: _email.text,
          password: _password.text,
          phone: _phone.text,
        );
    // The router is watching auth state and moves on its own.
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final Failure? failure = auth.failure;

    return Scaffold(
      appBar: AppBar(title: const Text('Register your school')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Start a 30-day trial. No card needed.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (failure != null) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          failure.message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    _Label('Your school'),
                    TextFormField(
                      controller: _school,
                      decoration: const InputDecoration(
                        hintText: 'e.g. City Parents High School',
                        prefixIcon: Icon(Icons.school_outlined),
                      ),
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      enabled: !auth.isBusy,
                      validator: (String? v) =>
                          (v == null || v.trim().length < 3)
                          ? 'Enter your school\'s name'
                          : null,
                    ),
                    const SizedBox(height: 20),

                    _Label('Your details'),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextFormField(
                            controller: _firstName,
                            decoration: const InputDecoration(
                              hintText: 'First name',
                            ),
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            enabled: !auth.isBusy,
                            validator: (String? v) =>
                                (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _lastName,
                            decoration: const InputDecoration(
                              hintText: 'Last name',
                            ),
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            enabled: !auth.isBusy,
                            validator: (String? v) =>
                                (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        hintText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      enabled: !auth.isBusy,
                      validator: (String? v) {
                        final String email = v?.trim() ?? '';
                        if (email.isEmpty) return 'Enter your email';
                        if (!email.contains('@') || !email.contains('.')) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(
                        hintText: 'Phone (optional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      enabled: !auth.isBusy,
                    ),
                    const SizedBox(height: 20),

                    _Label('Password'),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        hintText: 'At least 8 characters',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      enabled: !auth.isBusy,
                      validator: (String? v) => (v == null || v.length < 8)
                          ? 'Use at least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: _confirm,
                      decoration: const InputDecoration(
                        hintText: 'Confirm password',
                        prefixIcon: Icon(Icons.check_circle_outline),
                      ),
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      enabled: !auth.isBusy,
                      validator: (String? v) =>
                          v != _password.text ? 'Passwords do not match' : null,
                      onFieldSubmitted: (String _) => _submit(),
                    ),

                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: auth.isBusy ? null : _submit,
                      child: auth.isBusy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create school'),
                    ),

                    const SizedBox(height: 14),
                    Text(
                      'You will be the first administrator. Classes, terms and '
                      'the academic calendar are set up afterwards in the '
                      'DRAIS web app.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: auth.isBusy
                          ? null
                          : () => context.go(AppRoutes.login),
                      child: const Text('My school already uses DRAIS'),
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

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
