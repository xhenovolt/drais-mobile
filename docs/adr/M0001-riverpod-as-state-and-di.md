# M0001: Riverpod is both the state manager and the dependency injector

- **Status:** Accepted
- **Date:** 2026-08-05
- **Affects:** `lib/core/di/providers.dart`, every `application/` layer

## Problem

DRAIS Mobile needs a state management approach that will still be maintainable in ten years, by engineers who have not met the people who wrote it. It must support offline caching, background refresh, dependency injection, testing without a server, and modular feature development — and it must not require the whole team to learn a paradigm before they can add a screen.

Flutter offers no default. The choice is load-bearing: it shapes every feature written afterwards, and reversing it means rewriting the application layer.

## Context

- The app is a **client**. Its state is almost entirely server state plus a small amount of session and UI state. There is very little derived business state, because business logic lives on the server by design (see [M0004](M0004-no-business-logic-in-the-client.md)).
- The screens are the same shape as the web app's: fetch a school-scoped list, display it, mutate it, revalidate. LongTerm settled on SWR for exactly this shape ([ADR-0013](../platform/0013-swr-as-the-client-data-layer.md)).
- Testing matters more than usual here. LongTerm's own `CONTRIBUTING.md` is blunt that there is **no coverage of the ~685 API routes, RBAC/auth, or the portal isolation gate**. Mobile cannot inherit test confidence it does not have, so its own boundaries must be testable in isolation.
- The team is small. A second dependency-injection framework alongside a state manager is one more thing to keep in agreement.

## Decision

**Riverpod (`flutter_riverpod`) is both the state container and the dependency injector.** There is one object graph, declared in `lib/core/di/providers.dart`.

Concretely:

1. **Every dependency is a provider.** Storage, transport, repositories, controllers. Nothing is constructed inline in a widget, and there are no global singletons.
2. **Feature state is a `StateNotifier`** exposed through a `StateNotifierProvider`, holding an immutable state class. `AuthController` is the reference implementation.
3. **Async values that must exist before `runApp`** — `SharedPreferences`, `AppConfig` — are resolved in `bootstrap()` and injected as `ProviderScope` overrides. Their providers throw when unoverridden, so forgetting to bootstrap fails immediately and obviously instead of quietly reading empty storage.
4. **Tests override providers** rather than mocking constructors. A repository is typed as its domain interface precisely so a fake can replace it.
5. **No code generation.** `riverpod_generator` is not used. It buys terser declarations at the cost of a `build_runner` step in every checkout, every CI run, and every SDK upgrade for the next decade. The provider declarations are written out in full.

## Alternatives considered

**BLoC.** The most common enterprise answer, and genuinely good at modelling complex event-driven flows. Rejected because DRAIS Mobile has almost none: the ceremony of an event class, a state class and a mapper per interaction is a real cost paid on every screen, to model "fetch a list, show it". It would also make the DI question a separate one, since BLoC does not answer it.

**Provider (the package).** Simpler and already familiar to most Flutter developers. Rejected because it resolves dependencies through the widget tree — `context.read` — which makes non-widget code (a repository needing a logger) awkward, and because compile-time safety is weaker. Riverpod is its successor, written by the same author to fix exactly these problems.

**`get_it` + `ChangeNotifier`.** A service locator plus the framework's own primitive. Rejected: a service locator is a global mutable registry, so dependencies stop being visible at the call site and tests must remember to reset it. That is the "global singleton" pattern the brief asks to avoid unless justified.

**Riverpod 3.x.** Available, and the eventual destination. Deferred to keep 1.0.0's dependency surface on the version with the widest ecosystem support today; the migration is mechanical and is recorded in [ROADMAP](../ROADMAP.md).

## Trade-offs

- **Riverpod has a learning curve**, particularly `ref.watch` versus `ref.read` and provider lifetimes. Getting it wrong produces a rebuild loop or a stale read. This is the main cost, and the reason `providers.dart` documents the one genuinely subtle case (the `apiClientProvider` ↔ `authControllerProvider` cycle) in place.
- **Declaring providers by hand is verbose.** Accepted deliberately as the price of not owning a code-generation step for a decade.
- **`StateNotifier` is legacy in Riverpod 3.** It works and is well understood; migrating to `Notifier` is a known, contained follow-up.

## Consequences

- Any dependency can be replaced in a test with one `overrideWith` line, with no mocking framework.
- The whole object graph is readable in one file.
- Feature modules can be added without touching existing ones — a new feature declares its own providers and the graph absorbs them.
- Disposal is scoped: `NetworkInfo`'s subscription and `ApiClient`'s HTTP resources are released with the scope rather than leaked.

## Future considerations

The migration to Riverpod 3 and `Notifier` should happen before the codebase has many feature modules, since the cost scales with the number of controllers. It is a version bump plus a mechanical rewrite, not a design change.
