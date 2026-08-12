import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drais/core/di/providers.dart';
import 'package:drais/core/config/environment.dart';
import 'package:drais/core/constants/storage_keys.dart';
import 'package:drais/core/logging/app_logger.dart';
import 'package:drais/core/storage/preferences_store.dart';

/// Regression tests for the first-run gate.
///
/// ## The bug these exist for
///
/// The router decides where someone may be from three pieces of state: auth,
/// the selected server, and whether the welcome has been seen. Its redirect
/// only re-runs on navigation or when `refreshListenable` fires — and that
/// listenable watched the first two but **not** the third.
///
/// So finishing or skipping onboarding flipped a preference that nothing was
/// listening to. Nothing navigated, the redirect never re-ran, and both
/// buttons were dead. On a fresh install that is the entire app: there is no
/// other way past that screen. It shipped in a debug APK and was only caught
/// by running it.
///
/// The lesson is narrow and worth keeping: **a gate that reads state must
/// also observe it.** These tests pin the observation rather than the button,
/// because the button is easy to re-break from a distance.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<ProviderContainer> containerWith({required bool welcomeSeen}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (welcomeSeen) PreferenceKeys.welcomeSeen: true,
    });
    final PreferencesStore store = await PreferencesStore.open(
      const AppLogger('test', environment: Environment.development),
    );
    return ProviderContainer(
      overrides: <Override>[preferencesStoreProvider.overrideWithValue(store)],
    );
  }

  test('a fresh install has not seen the welcome', () async {
    final ProviderContainer container = await containerWith(welcomeSeen: false);
    addTearDown(container.dispose);

    expect(container.read(welcomeSeenProvider), isFalse);
  });

  test('finishing onboarding flips the flag the router reads', () async {
    final ProviderContainer container = await containerWith(welcomeSeen: false);
    addTearDown(container.dispose);

    expect(container.read(welcomeSeenProvider), isFalse);

    await container.read(preferencesStoreProvider).setWelcomeSeen();
    container.invalidate(welcomeSeenProvider);

    expect(
      container.read(welcomeSeenProvider),
      isTrue,
      reason: 'the gate must see the new value after invalidation',
    );
  });

  test('a listener on the flag is notified when onboarding completes',
      () async {
    // This is the exact wiring that was missing. `_AuthRefreshNotifier` is
    // private, so this asserts the property it depends on: that listening to
    // `welcomeSeenProvider` actually delivers the change. If this fails, the
    // router cannot possibly re-run its redirect and onboarding is a dead end
    // again.
    final ProviderContainer container = await containerWith(welcomeSeen: false);
    addTearDown(container.dispose);

    final List<bool> observed = <bool>[];
    final ProviderSubscription<bool> subscription = container.listen<bool>(
      welcomeSeenProvider,
      (bool? previous, bool next) => observed.add(next),
      fireImmediately: false,
    );
    addTearDown(subscription.close);

    await container.read(preferencesStoreProvider).setWelcomeSeen();
    container.invalidate(welcomeSeenProvider);
    // Riverpod recomputes an invalidated provider on the next microtask when
    // something is listening, so let that settle before asserting.
    await Future<void>.delayed(Duration.zero);

    expect(
      observed,
      <bool>[true],
      reason: 'the router listens to this to re-run its redirect',
    );
  });

  test('the flag survives a rebuilt store, so onboarding is shown once only',
      () async {
    final ProviderContainer first = await containerWith(welcomeSeen: false);
    await first.read(preferencesStoreProvider).setWelcomeSeen();
    first.dispose();

    // A second store over the same backing preferences — the next launch.
    final PreferencesStore next = await PreferencesStore.open(
      const AppLogger('test', environment: Environment.development),
    );
    final ProviderContainer second = ProviderContainer(
      overrides: <Override>[preferencesStoreProvider.overrideWithValue(next)],
    );
    addTearDown(second.dispose);

    expect(second.read(welcomeSeenProvider), isTrue);
  });
}
