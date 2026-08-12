# Contributing to DRAIS Mobile

The practical guide to working on DRAIS Mobile: setup, tests, conventions, and the rules a review will reject a change over.

For *what* DRAIS Mobile is, read the [README](README.md). For *why* it is built this way — read before changing any subsystem — read the [mobile ADRs](docs/README.md) and the [inherited platform decisions](docs/platform/README.md).

This document follows the shape of [LongTerm's `CONTRIBUTING.md`](docs/platform/LONGTERM_CONTRIBUTING.md) on purpose. An engineer moving between the two repositories should not have to learn two sets of conventions.

## Setup

```bash
flutter pub get
flutter run --dart-define-from-file=env/development.json
```

Requires Flutter 3.44+ / Dart 3.12+. There is **no code generation** — `flutter pub get` and `flutter test` are the entire toolchain ([M0005](docs/adr/M0005-hand-written-serialization.md)).

### Running against a backend

| Target | How |
|---|---|
| Local `next dev`, Android emulator | Default. `10.0.2.2` is the emulator's alias for host loopback. |
| Local `next dev`, physical device | Put your machine's LAN address in `env/development.json`; both must be on the same network. |
| Staging / QA / production | `--dart-define-from-file=env/<name>.json` |

See [ENVIRONMENTS](docs/ENVIRONMENTS.md). Configuration is fixed at **build time** — there is no runtime server switcher, and there must not be one.

## Tests

```bash
flutter test                    # everything
flutter test test/core/         # one area
```

Test the seams, not the framework:

| What | Why |
|---|---|
| DTO parsing | Every backend shape quirk deserves a case ([PARITY](docs/PARITY.md)) |
| Permission semantics | Must match the server exactly, in both directions |
| Error classification | Code and status mapping |
| Redaction | A security control, tested like one |
| Configuration validation | The failure cases matter more than the happy path |

**What is not covered:** there are no widget tests, no integration tests, and no tests against a live backend. Treat changes to navigation, screens, or the interceptor chain as needing manual verification — and say so in the PR rather than implying coverage that does not exist.

Mobile also inherits a gap it cannot close: LongTerm has **no test coverage of its API routes, RBAC or auth** ([PARITY §3.6](docs/PARITY.md)). A backend change can break this client silently.

## The non-negotiables

A review must reject a change that breaks any of these. Full list in [CODING_STANDARDS](docs/CODING_STANDARDS.md).

- **All HTTP goes through `ApiClient`.** No feature constructs a `Dio`.
- **Repositories return `Result<T>` and never throw.**
- **No business logic in the client.** The reviewer's question is: *where did this number come from?* ([M0004](docs/adr/M0004-no-business-logic-in-the-client.md))
- **Never send `school_id`.** The server derives it from the session.
- **Permission checks decide what to draw, never what is allowed.**
- **No `print`** — use `AppLogger`. **Never log a credential.**
- **Nothing credential-shaped in `SharedPreferences`** — `SecureStore` or nowhere.
- **Paginate every list endpoint.**
- **Clear the cache on sign-out.**

## Adding a feature module

The full sequence is in [ROADMAP](docs/ROADMAP.md) → "How to add a module". The short version:

**Read the backend first** — its routes under `src/app/api/<module>/`, its library under `src/lib/<module>/`, and its ADRs. Then work outward: entities → repository interface → DTOs → data source → repository → controller → screens → providers → route.

Add the endpoints to `lib/core/config/api_endpoints.dart`, mirroring the route paths **exactly**. A renamed concept is a concept two engineers will fail to connect.

## Consuming a new endpoint

1. Read the route file in LongTerm. Note the response shape — there are [three](docs/PARITY.md#33-three-response-envelope-shapes-coexist-—-medium) — the permission code it gates on, and its pagination parameters.
2. Add the path to `ApiEndpoints` with a comment naming the source file.
3. Write the DTO by hand, commenting each quirk and citing the route.
4. If you find a new backend inconsistency, **add it to [PARITY §3](docs/PARITY.md)**. That document is how the platform learns what its clients are working around.
5. Update `AppVersion.verifiedAgainstLongTerm` if you re-audited against a newer LongTerm version.

## Versioning and commits

Same rules as LongTerm — see [VERSIONING](docs/VERSIONING.md):

| Segment | When |
|---|---|
| MAJOR | breaking change (`feat!:`, `fix!:`, or `BREAKING CHANGE`) |
| MINOR | new feature (`feat:`) |
| PATCH | everything else — default |

Unlike LongTerm there is **no pre-commit hook**; the version is bumped by hand. Update `pubspec.yaml` and `lib/core/constants/app_version.dart` **together** — they duplicate the version because the `User-Agent` cannot await an async lookup, and a mismatch is caught only in review.

Increment the build number (`+N`) on every store upload, including a re-upload of an identical version. Both stores reject a repeated build number.

Tag releases `mobile-v1.0.0`, so mobile and platform tags stay distinguishable.

## Documentation

- **Changing behaviour?** Update the doc comment. In-code documentation beats `docs/` — it is closer to the code and more likely to stay true.
- **Making an architectural decision?** Write an ADR — copy [`docs/adr/TEMPLATE.md`](docs/adr/TEMPLATE.md). "Architectural" means it constrains future work, will look wrong to someone who wasn't there, or trades something away deliberately.
- **Comments explain why, never what.** Restating the code is noise; recording what you traded away is the whole value.
- **Working around a backend quirk?** Cite the route in the comment *and* record it in [PARITY](docs/PARITY.md).
- **Never edit `docs/platform/`.** Those are copies. Edit the original in LongTerm and re-copy.

## Localization

LongTerm requires every user-facing string in **both English and Arabic**, with dictionaries in `src/locales/{en,ar}.json`.

Mobile does not yet have a localisation layer — a known gap in [ROADMAP](docs/ROADMAP.md). Until it lands: keep user-facing strings short, plain and grouped per screen so extraction is mechanical, and **never concatenate sentence fragments** — they do not survive translation and they break under RTL.

## Before you push

```bash
flutter analyze && flutter test
```

Both must be clean. Then check that the docs still describe what the code does.
