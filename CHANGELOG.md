# Changelog

All notable changes to DRAIS Mobile are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows the same MAJOR/MINOR/PATCH rules as DRAIS LongTerm, on an independent number line — see [docs/VERSIONING.md](docs/VERSIONING.md).

## [Unreleased]

## [1.7.2] — 2026-08-12

### Removed — the DEVELOPMENT corner stripe

A diagonal environment banner sat across the top-right corner of every screen
on any non-production build. It was covering UI on a build people are actually
using, and the question it answered — which build is this — is answered
properly on About, in the drawer footer, and in the copied diagnostics, none of
which cost a corner of the interface.

### Added — version increments are now enforced, not remembered

The app sat on `1.0.0+1` through six milestones because bumping it meant
editing three files consistently and nothing ever objected. A convention
nothing enforces is a hope, so:

- **`tool/bump_version.dart`** — `dart run tool/bump_version.dart patch`
  (or `minor`, `major`, `build`, or an explicit `X.Y.Z`) updates
  `pubspec.yaml`, `lib/core/constants/app_version.dart` and its version-quoting
  doc comments, and opens a dated `CHANGELOG.md` section. The build number
  always increments and never resets, per docs/VERSIONING.md.
- **`test/core/app_version_test.dart`** — fails the suite if `AppVersion` and
  `pubspec.yaml` disagree, if the version is malformed, or if `CHANGELOG.md`
  has no section for the current version. Patches included: a shipped build
  whose number appears nowhere in the changelog cannot be explained later.

### Changed — APKs are named after what they are

`app-debug.apk` said nothing; two builds a week apart shared a filename, so
the one in someone's Downloads folder was unidentifiable and a bug report
against it could not be placed. Artefacts now come out as
**`drais-1.7.2-debug.apk`**.

AGP 9 removed the `applicationVariants` API this is usually done with, so
`android/app/build.gradle.kts` uses the current variant API, falling back to
`unversioned` rather than stamping `null` into a filename if a variant has no
version name.


## [1.7.1] — 2026-08-12

### Fixed — onboarding was a dead end on a fresh install

Neither **Skip** nor **Get started** did anything. On a new device that is the
whole app: there is no other way past that screen.

The router's redirect decides where someone may be from three pieces of state
— auth, the selected server, and whether the welcome has been seen — but it
only re-runs on navigation or when its `refreshListenable` fires, and that
listenable observed the first two and not the third. Finishing onboarding
flipped a preference nothing was listening to, so no navigation happened and
the redirect never re-ran. The comment in the handler asserted "the router
watches this flag and moves on by itself"; it did not.

Fixed on both sides, deliberately:

- `_AuthRefreshNotifier` now listens to `welcomeSeenProvider` as well, so the
  gate observes every piece of state it reads.
- The handler also navigates explicitly, so the only exit from a fresh install
  does not depend on a listener elsewhere staying wired up.

Four regression tests in `test/app/first_run_gate_test.dart` pin the
observation rather than the button, including that a listener on the flag is
actually notified — the precise property whose absence caused this.

This shipped in a debug APK and was found by running it, not by the 107 tests
that passed over it.

## [1.7.0] — 2026-08-12

### Added — About route, and the version where people can see it

- **`/about`** — version, build, the LongTerm version this client was verified
  against, data mode with the database host, the signed-in identity and its
  role/permission counts, live module coverage read from the catalogue, and
  the open-source licence list. A one-tap **Copy diagnostics** action puts all
  of it on the clipboard, deliberately excluding credentials and the session.
- The version now shows in the **drawer footer** on every screen, and tapping
  it opens About. "Which version are you on?" is the first question on every
  support call, and until now a phone had no way to answer it.

### Fixed — cross-school leak in unidentified punches (security)

`unmatchedPunches()` had **no tenant filter at all**. The doc comment claimed
`attendance_raw_events` has no `school_id` column and that the scope came from
the device; neither was true — the column exists and no device join was
present. Against the live database the query returned **479 punches across all
schools** where the correct answer for the requesting school was **0**.

Every attendance query now scopes on `e.school_id`, the same column the
platform uses. The `students`/`staff` UNION subqueries are gone: they were
slower, and they could never have scoped an *unmatched* punch, which by
definition has no person to join through.

### Changed — the Attendance Health Score is now the platform's, not mine

The device-health heuristics written for the first cut of Time Health — 4-hour
silence, 60-second skew, 50% under-reporting, a 10-day baseline threshold —
were **invented locally**. They had no counterpart in LongTerm, so mobile and
web could report different verdicts on the same school with no way to tell
which was right.

Replaced with a transcription of `src/lib/attendance/health.ts`:

- All **ten** weighted checks — devices, heartbeats, attendance flow, time
  synchronization, SMS, identity mapping, notification queue, background jobs,
  database, device clock reputation.
- The real bands (`>= 90` healthy, `>= 70` degraded), the real weights, and
  each check's own score ladder.
- `unknown` checks excluded from the rollup rather than scored as zero, so a
  check that could not run is not treated as evidence of a problem.
- Recommendations sorted worst-score-first, as the platform sorts them.
- `computeOverallHealth` is pure and covered by 13 tests that pin every band
  and weight, so a platform change to any threshold fails a test here.

Surfaced on Time Health as a scored ring with the ranked recommendations under
it and every individual check expandable. Verified against the live database:
all ten queries run, and the busiest school scores its heartbeat 20 and flow 25
because its only device last reported 26 hours ago — which is exactly the
condition the screen exists to reveal.

`AttendanceTrendDay.isUniform` remains mobile-only and is now **documented as
such** rather than sitting silently among the transcribed logic. It is a hint
on a chart; nothing is written back from it.

### Changed

- `verifiedAgainstLongTerm` → `1.173.45`.
- `pubspec.yaml` → `1.7.0+8`, catching the version up to the features actually
  shipped: direct mode, the Dart server, the navigation shell and theming,
  onboarding and school registration, phase 1 students, phase 2 attendance.


### Added — DRAIS Server, a Dart backend (`server/`)

Phase 1 of a strangler migration off Node.js. Authentication only; the Next.js
application still owns every other route and this service runs beside it.

- `shelf` + `shelf_router` HTTP service implementing `/api/health`,
  `/api/auth/login`, `/api/auth/me`, `/api/auth/logout` — matching the platform
  contract exactly, so the Flutter client works against it **unchanged**.
- TiDB Cloud access over TLS via `mysql_client`, with `?` → `:pN` binding and a
  guard that rejects bound `LIMIT`/`OFFSET` (the TiDB trap from ADR-0010) at
  development time rather than in production.
- Session creation and validation reproducing `getSessionSchoolId()`, including
  the gates applied on **every** request: soft-deleted school, suspended school,
  lapsed subscription. Sessions do not slide, matching the platform.
- RBAC with wildcard expansion identical to the client's `PermissionSet` and
  LongTerm's `expandPermissionChain`.
- 18 tests; `dart analyze` clean.
- Startup failures exit with a reason and an actionable fix instead of a stack
  trace: 78 misconfigured, 69 database unreachable, 73 port in use.

**Verified against the live TiDB instance:** connection 327 ms; the session
query (EXISTS subquery, four joins) 231 ms; and — the result that decided
viability — **Dart verifies password hashes produced by Node's `bcryptjs`**,
so the 38 existing users sign in with their current passwords, with no reset
and no migration.

**Correction carried into the Dart implementation:** `/api/auth/login` computes
`isSuperAdmin` with the same three-way test as the session query, instead of
matching role names against `'admin'` (PARITY §3.2).

### Removed — JavaScript

- Deleted the Flutter `web/` target (`index.html`). The app contains no
  JavaScript, no HTML and no JS runtime.
- Removed unused dependencies: `cupertino_icons`, `package_info_plus` — neither
  was imported anywhere.

### Changed — dependencies

- `flutter_secure_storage` 9.2.4 → 10.3.1. Fixes a Linux desktop build failure:
  the old `flutter_secure_storage_linux` bundled a `json.hpp` that modern Clang
  rejects. `encryptedSharedPreferences` is gone in v10 — Google deprecated
  Jetpack Security and the plugin now applies its own ciphers, migrating
  existing entries on first access.
- `go_router` 14.8.1 → 17.4.0, `connectivity_plus` 6.1.5 → 7.3.1.
- Dropped the discontinued transitive `js` package.
- `flutter_riverpod` stays on 2.x; 3.x removes `StateNotifier` and is a
  separate migration (M0001, "future considerations").

  The upgrade also removes the `libsecret-1-dev` / `libjsoncpp-dev` build
  requirement on Linux desktop — verified by a clean `flutter build linux`
  with neither package installed.

### Added — direct database mode (no server)

The app can now talk to TiDB Cloud in-process, with no DRAIS server and no
connect screen — the topology of the Next.js desktop build, where the API
routes run inside the executable.

- `DirectDbConfig` reads TiDB settings from a provisioned `drais.env` (beside
  the executable, or the app support directory). **Never a `--dart-define`:**
  those are compiled into the binary, and an APK is an archive. Absence of the
  file is the normal case and simply means API mode.
- `DraisDatabase` — in-process TiDB pool over TLS, mapping driver errors into
  the app's existing `Failure` types so a database error reaches the UI exactly
  as an HTTP one does, and carrying the same `LIMIT ?` guard (ADR-0010).
- `AuthDirectRepository` implements the same `AuthRepository` as the HTTP one,
  so nothing above `data/` knows which is in use. Sessions are real rows in
  `sessions` — visible and revocable from the web app — with the token held in
  the keystore instead of a cookie.
- The router skips the connect screen entirely in direct mode; the mode is
  derived from the config's presence and cannot get out of step.
- `assets/drais.env` is read as a last-resort fallback, so a **distributed APK
  is self-contained**: install, open, sign in — no server, no file to place.
  Filesystem locations still take priority, so one device can be repointed
  without a rebuild.

**Security note:** direct mode puts a database credential on the device and
moves tenant isolation and permission checks into the client. Appropriate for a
school-controlled desktop; not for a personal handset. See
[`docs/DEPLOYMENT_MODES.md`](docs/DEPLOYMENT_MODES.md).

### Fixed — a release APK would have had no network access

`INTERNET` was declared only in the debug and profile manifests, which is
Flutter's default. A **release** build would have compiled, installed and then
failed every connection at runtime — in direct mode, that means the app cannot
reach TiDB at all. Added `INTERNET` and `ACCESS_NETWORK_STATE` to the main
manifest, and set the app label to `DRAIS`.

### Fixed — every active user was told "your account is pending approval"

`users.is_active` is `tinyint(1)` and the MySQL driver returns it as a Dart
**bool**, not an int. Reading it through an int coercion yielded null:

- **Server:** `asInt(is_active) ?? 0` → `0` → every one of the 34 active users
  was rejected at login.
- **Direct mode:** `asInt(is_active) == 0` → false → the mirror-image bug, in
  which a *deactivated* account would have been allowed to sign in.

Both now coerce through `asBool`, which handles `bool`, `0`/`1` and `'0'`/`'1'`.
Verified against production: 34 active users sign in, 2 deactivated ones are
correctly refused. Covered by `test/core/sql_value_test.dart`.

### Added — switching servers

- **Change server** on the login screen (every environment) and in the
  dashboard's ⋮ menu. Without it, a device pointed at the wrong server had no
  way back except reinstalling.
- `switchServer()` orders the steps correctly: sign out **first**, while the
  old address is still known so the session is invalidated on the server that
  issued it, then clear the address. The response cache goes too — the next
  server may be a different school.
- The login screen names the connected host, with a lock icon for HTTPS and a
  network icon for a LAN address.
- [`docs/DEPLOYMENT_MODES.md`](docs/DEPLOYMENT_MODES.md) — hosted vs. own
  server, and where credentials live in each.

### Changed — no localhost, ever

- **Removed the compile-time default server address.** `AppConfig` no longer falls back to `http://10.0.2.2:3000`; `DRAIS_API_BASE_URL` is now an optional *default*, and a build without one is valid. Guessing an address is what silently pointed builds at a developer's machine.
- **`env/development.json` no longer names a server.** A developer enters their address once on the connect screen and it is remembered.

### Added — runtime server selection

- `ServerConfig` / `ServerController` — the DRAIS server is resolved at runtime: a user's stored choice, then the build default, then nothing. The app opens and renders with no server at all, because every screen is compiled into the binary.
- **Connect screen** (`/connect`), the outermost router gate. Accepts a hosted address (`drais.pro`) or a school's own server on the LAN (`192.168.1.50:3210`).
- `ServerProbe` — verifies a candidate is genuinely DRAIS via `/api/health` before storing it, and reports whether that server can reach its own database. A wrong address usually *does* answer; "connection successful" against a home router would be worse than useless.
- Cleartext `http` accepted on private networks, refused to public hosts. Addresses pointing at the device itself are rejected — nothing on a phone hosts DRAIS.
- `ApiClient` takes its origin at construction and is rebuilt when the server changes, so no request can be left addressed to the old server.

### Removed

- The embedded Node.js experiment (`packages/drais_node`). DRAIS Mobile is a native client of a remote DRAIS server; it embeds no JavaScript runtime and no server.

### Documentation

- [`docs/FLUTTER_FIRST_ASSESSMENT.md`](docs/FLUTTER_FIRST_ASSESSMENT.md) — architectural assessment, what stays server-side, persistence recommendation, and a phased plan.

## [1.0.0] — 2026-08-05

**The birth of the DRAIS mobile platform.** Establishes DRAIS Mobile as a first-class client of the DRAIS ecosystem.

Verified against DRAIS LongTerm **1.173.15**.

This release is the **foundation only**. It ships no business module by design: attendance, finance, students, timetable and messaging are planned in [docs/ROADMAP.md](docs/ROADMAP.md) and build on the layers below rather than beside them.

### Added — architecture

- Feature-first Clean Architecture: `presentation/` → `application/` → `domain/` ← `data/`, over shared `core/` and `shared/` layers. Dependencies point inward; `domain/` imports nothing.
- Riverpod as both state manager and dependency injector; the whole object graph declared in `lib/core/di/providers.dart`. No global singletons. ([M0001](docs/adr/M0001-riverpod-as-state-and-di.md))
- `bootstrap()` startup sequence: configuration validation, storage initialisation, framework and platform error handlers, then `runApp`.

### Added — networking

- `ApiClient` — the single HTTP entry point, mirroring the mandatory-wrapper rule of `src/lib/apiClient.ts`. Supports `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, multipart upload with progress, and pagination.
- Interceptor chain, ordered deliberately: cookies → session detection → retry → logging.
- `ApiEnvelope` — parses all three response shapes LongTerm emits, including 200-with-`success:false`.
- `RetryInterceptor` — exponential backoff with jitter, **idempotent methods only**. Writes are never retried, because the internal API has no idempotency mechanism.
- `PageRequest` / `PagedResult` matching the backend's `page`/`limit` convention.
- Per-request correlation id sent as `X-Request-Id` and carried in every log line, joinable to LongTerm's `system_logs`.
- `X-DRAIS-Client` / `X-DRAIS-Client-Version` headers, and a distinguishable `User-Agent` so mobile activity is attributable in `sessions.device_info` and `audit_logs`.

### Added — authentication

- Full parity with the platform's school-auth flow: login, logout, session restoration, forced password change, sign-out on session expiry. ([M0002](docs/adr/M0002-cookie-session-parity.md))
- Cookie-based session handling with the jar persisted in the **platform keystore**, not in files — `drais_session` is a seven-day bearer credential.
- Login is two calls: `/api/auth/login` establishes the session, `/api/auth/me` loads the identity. The login payload's `isSuperAdmin` is deliberately ignored ([PARITY §3.2](docs/PARITY.md)).
- `PermissionSet` reproducing the server's wildcard chain exactly — exact code, prefix wildcards, universal grant — for rendering decisions only.
- `Role.isSuperAdmin` reproducing the server's three-way test (`is_super_admin` / `slug` / canonical name).
- `AuthStatus.offlineUnverified`: a session that cannot be verified is **kept**, not signed out.

### Added — error handling

- Sealed `Failure` hierarchy separating network, timeout, authentication, authorization, subscription, validation, not-found, conflict, server, malformed-response, cancellation and unknown failures — each carrying a user message and a separate technical detail.
- `Result<T>` returned by every repository; nothing throws across a layer boundary.
- `ApiErrorCode` mirroring both the canonical `src/lib/apiResponse.ts` enum and the codes the hand-written auth routes emit.
- `ErrorView` rendering any `Failure`, with technical detail available outside production only.

### Added — storage and offline

- `SecureStore` (keystore), `PreferencesStore` (non-sensitive), `CacheStore` (read cache), `CookieStore` (session jar) — separated by class so the distinction cannot be forgotten.
- Read-through response cache serving the last successful body on network failure. Cleared on sign-in and sign-out.
- Offline writes are **not** implemented; the reasoning and the path forward are in [docs/OFFLINE_STRATEGY.md](docs/OFFLINE_STRATEGY.md).

### Added — logging

- `AppLogger` with levels mirroring `src/lib/systemLogger.ts`.
- `Redaction` — unconditional in every environment, masking session cookies, bearer tokens, passwords, long hex tokens and partial emails, recursing through nested structures.
- Production drops debug logs and never emits request or response bodies; failures are always logged.

### Added — navigation and UI

- `go_router` with **every** auth gate in one redirect: session, forced password change, incomplete setup, lapsed subscription, offline. Paths mirror the web routes. ([M0003](docs/adr/M0003-go-router-navigation.md))
- Screens: splash, login, change password, access blocked, dashboard, diagnostics.
- Material 3 theme from the DRAIS brand seed, light and dark.
- Non-production builds visibly marked, with a diagnostics screen and a live `/api/health` probe.

### Added — configuration

- Four environments — development, staging, QA, production — switched by `--dart-define-from-file` alone.
- `AppConfig.validate()` refuses to start a production build that is misconfigured, points at a local address, or would send the session cookie over cleartext.
- Database credentials, API secrets and SMS/email keys are **structurally excluded**; the app never opens a database connection. ([M0004](docs/adr/M0004-no-business-logic-in-the-client.md))

### Added — documentation

- Five mobile ADRs, seven guides, and 16 inherited platform documents in `docs/platform/`.
- [docs/PARITY.md](docs/PARITY.md), recording nine items of technical debt observed in LongTerm 1.173.15 that affect mobile.
- `CONTRIBUTING.md` following the shape of LongTerm's.

### Testing

45 unit tests covering permission semantics, envelope parsing, error-code classification, redaction and configuration validation. `flutter analyze` is clean under a strict analyser configuration.

### Known limitations

- Business modules are not implemented — see [docs/ROADMAP.md](docs/ROADMAP.md).
- Offline is read-only.
- User-facing strings are English-only; LongTerm requires English **and** Arabic. Recorded in [docs/ROADMAP.md](docs/ROADMAP.md).
- No push notifications; the server has no device-token endpoint yet.
- Password reset is web-only, because no mobile-reachable flow exists server-side.

[Unreleased]: https://github.com/xhenvolt/drais-mobile/compare/mobile-v1.0.0...HEAD
[1.0.0]: https://github.com/xhenvolt/drais-mobile/releases/tag/mobile-v1.0.0
