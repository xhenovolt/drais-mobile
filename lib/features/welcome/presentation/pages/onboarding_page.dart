import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:drais/app/router/routes.dart';
import 'package:drais/app/theme/app_theme.dart';
import 'package:drais/core/di/providers.dart';

/// One onboarding slide.
class _Slide {
  const _Slide({required this.asset, required this.title, required this.body});

  /// Path to the illustration.
  final String asset;

  /// Short headline — a capability, not a feature name.
  final String title;

  /// One sentence saying what it means for the person holding the phone.
  final String body;
}

/// Introduces DRAIS to someone who has never used it.
///
/// ## Shown once, to first-time users only
///
/// The device flag is set when this finishes, and the router never routes here
/// again. Someone who already knows DRAIS — the common case, since staff are
/// provisioned by an administrator — sees the welcome and goes straight on.
///
/// ## Why these three
///
/// Each slide answers a question a Ugandan school actually asks before
/// installing: *does it save me time on the register*, *will it tell me
/// anything useful*, and *does it work here*. Nothing explains what a school
/// management system is; the audience already runs one.
class OnboardingPage extends ConsumerStatefulWidget {
  /// Creates the onboarding flow.
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _controller = PageController();
  int _index = 0;

  static const List<_Slide> _slides = <_Slide>[
    _Slide(
      asset: 'assets/illustrations/onboarding_attendance.svg',
      title: 'Take the register in seconds',
      body:
          'Mark a whole class from your phone, or let the biometric devices '
          'do it for you. Present, late and absent — captured as it happens.',
    ),
    _Slide(
      asset: 'assets/illustrations/onboarding_insight.svg',
      title: 'Know your school at a glance',
      body:
          'Daily and weekly attendance, class by class, without waiting for '
          'anyone to compile a report.',
    ),
    _Slide(
      asset: 'assets/illustrations/onboarding_anywhere.svg',
      title: 'Works the way your school works',
      body:
          'Connect to your school\'s own DRAIS server on site, or to DRAIS '
          'online. The same records either way.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _slides.length - 1;

  Future<void> _finish() async {
    await ref.read(preferencesStoreProvider).setWelcomeSeen();
    ref.invalidate(welcomeSeenProvider);

    // Navigate explicitly rather than relying on the redirect firing off the
    // invalidation alone. Both paths work now, but this button is the only
    // way out of a fresh install: if it ever depends solely on a listener
    // somewhere else staying wired up, a change over there strands every new
    // user on this screen with no way forward. It did exactly that once.
    if (!mounted) return;
    context.go(AppRoutes.splash);
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient(isDark: isDark),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              // Skip is always available. Someone who has used DRAIS on the
              // web does not need three screens explaining it, and making
              // them swipe would be the first thing the app asks of them.
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: TextButton(
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                ),
              ),

              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (int i) => setState(() => _index = i),
                  itemBuilder: (BuildContext context, int i) =>
                      _SlideView(slide: _slides[i]),
                ),
              ),

              _PageDots(count: _slides.length, index: _index),
              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_isLast ? 'Get started' : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Expanded(
            flex: 5,
            child: Center(
              child: SvgPicture.asset(
                slide.asset,
                // Bounded so a tall phone does not stretch the artwork and a
                // short one does not crowd the text off the screen.
                width: 300,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            slide.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            slide.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

/// Page indicator. The active dot widens rather than only changing colour, so
/// position is legible without relying on colour perception.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (int i) {
        final bool active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
