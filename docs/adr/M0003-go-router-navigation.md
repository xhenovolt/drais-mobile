# M0003: Navigation is declarative, and every auth gate is a router redirect

- **Status:** Accepted
- **Date:** 2026-08-05
- **Affects:** `lib/app/router/`

## Problem

The app needs deep linking, authentication guards, role-aware routing, and room for a dozen future modules. The failure mode to avoid is the common one: a screen that decides for itself whether the user may be there, so that a second route into the same screen — a deep link, a notification tap, a back-stack restoration — arrives without the check.

## Context

- LongTerm centralises this in `middleware.ts`: one file lists `PUBLIC_ROUTES`, gates setup-incomplete users, redirects on `drais_force_reset`, and applies role guards from the `drais_role` cookie. Every web request passes through it.
- Mobile has the same gates to enforce — session, forced password change, incomplete setup, lapsed subscription — plus a state the web does not have: **a valid session that cannot currently be verified because the device is offline**.
- Push notifications and shared links will eventually open specific screens directly, so route paths must be addressable and guarded independently of how they were reached.

## Decision

**`go_router`, with every gate expressed as a single `redirect` callback.** No screen navigates as a consequence of authentication.

1. **One `redirect` function** reads `AuthState` and returns either null ("stay") or a destination. It runs on every navigation *and* — via `refreshListenable` — on every auth state change.
2. **Auth state drives navigation, not the reverse.** `LoginPage` calls `login()` and does nothing else; the router notices `AuthStatus.authenticated` and moves. This is why there is no path into an authenticated screen that skips the check.
3. **Paths mirror the web app** (`/login`, `/dashboard`, `/profile`, `/attendance`) so a URL means one thing across the platform.
4. **`refreshListenable` bridges Riverpod**, rather than watching auth state in the router provider. Watching would rebuild the whole `GoRouter` on every auth change and destroy the back stack.
5. **`AuthStatus.offlineUnverified` proceeds into the app.** The user keeps their session and sees cached data with a banner. This is the state the web middleware has no equivalent for, and getting it wrong would sign out every teacher in a classroom with no signal.

## Alternatives considered

**Imperative `Navigator` 1.0.** Simple and familiar. Rejected: deep linking is manual, and guards inevitably end up duplicated across screens, which is precisely the bug class described above.

**`auto_route`.** Type-safe routes and generated navigation — genuinely nicer call sites. Rejected because it requires `build_runner`, which is the same decade-long cost weighed in [M0001](M0001-riverpod-as-state-and-di.md). `go_router` is maintained by the Flutter team and needs no generation step.

**Beamer.** Capable, considerably smaller community. Not enough advantage to accept the ecosystem risk on a ten-year project.

**Guards on each route rather than one global redirect.** More granular. Rejected because the interesting conditions (session, password change, subscription) are global, and per-route guards mean the same three checks copied into every route definition — with one eventually missing.

## Trade-offs

- **The redirect function is a single point of failure.** A wrong branch can strand a user or loop. Mitigated by making it exhaustive over `AuthStatus` — the compiler rejects an unhandled state — and by every branch returning a destination that is itself terminal.
- **Route-level role gating is not implemented in 1.0.0**, because there are no role-gated routes yet. The mechanism is `AuthUser.can()`, and the place to apply it is this redirect. Adding it later touches one file.
- **Debugging redirects can be opaque.** `debugLogDiagnostics` is enabled outside production for exactly this reason.

## Consequences

- Every screen can assume the user is permitted to be there — because the router already decided.
- Deep links get the same gates as ordinary navigation, for free.
- A new module adds a `GoRoute` and, if it needs one, a permission check in one place.

## Note on what these gates are

**They are user experience, not security.** The router decides what to *draw*. Whether data is served is decided by `getSessionSchoolId()` and `requirePermission()` on the server, independently, on every request. A tampered client reaches prettier screens and identical 403s.
