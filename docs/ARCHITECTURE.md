# DRAIS Mobile architecture

DRAIS Mobile is **a presentation layer of the DRAIS platform**, not an independent application. The server owns the data, the rules and the access decisions; this app renders them on a phone.

Read [M0004](adr/M0004-no-business-logic-in-the-client.md) before changing anything. It is the rule the rest of this document serves.

## The shape

```
┌──────────────────────────────────────────────────────────┐
│  presentation/   widgets, pages, routing                 │
│                  knows: application layer                │
├──────────────────────────────────────────────────────────┤
│  application/    controllers, immutable state            │
│                  knows: domain layer                     │
├──────────────────────────────────────────────────────────┤
│  domain/         entities, repository interfaces         │
│                  knows: nothing                          │
├──────────────────────────────────────────────────────────┤
│  data/           DTOs, data sources, repository impls    │
│                  knows: domain + core                    │
├──────────────────────────────────────────────────────────┤
│  core/           transport, storage, errors, logging, DI │
│  shared/         cross-feature widgets and helpers       │
└──────────────────────────────────────────────────────────┘
```

Dependencies point **inward**. `domain/` imports nothing from the layers around it, which is what makes it — and everything defined in terms of it — testable without a server, a device or a widget tree.

## Feature-first, not layer-first

```
lib/features/auth/
├── data/           dtos/  datasources/  repositories/
├── domain/         entities/  repositories/
├── application/    auth_controller.dart  auth_state.dart
└── presentation/   pages/  widgets/
```

Everything about authentication is in one directory. A new module — attendance, finance — is a sibling with the same four sub-directories, and it can be built without touching what exists. The alternative (`lib/models/`, `lib/screens/`, `lib/services/`) means every feature is smeared across the tree and every change touches four distant folders.

## Directory map

| Path | Contains | Notes |
|---|---|---|
| `lib/main.dart` | Entry point | One line; everything is in `bootstrap()` |
| `lib/bootstrap.dart` | Startup sequence | Config validation, storage, error handlers, `runApp` |
| `lib/app/` | Root widget, router, theme | `app_router.dart` holds **every** navigation gate |
| `lib/core/config/` | `AppConfig`, `Environment`, `ApiEndpoints` | Build-time configuration; `ApiEndpoints` mirrors `src/app/api/` |
| `lib/core/constants/` | Version, storage keys | Every persisted key is declared once here |
| `lib/core/error/` | `Failure`, `Result`, `ApiErrorCode` | Sealed hierarchies — exhaustive switching, no codegen |
| `lib/core/logging/` | `AppLogger`, `Redaction` | Redaction is unconditional, in every environment |
| `lib/core/network/` | `ApiClient`, envelope, interceptors, pagination | The only HTTP in the app |
| `lib/core/storage/` | Secure store, preferences, cache, cookies | Credential-grade values are separated by *class*, not convention |
| `lib/core/di/` | `providers.dart` | The whole object graph, in one file |
| `lib/features/` | Feature modules | `auth`, `dashboard`, `diagnostics` today |
| `lib/shared/` | Cross-feature widgets | `ErrorView`, `LoadingView`, `NoticeBanner` |
| `env/` | Per-environment dart-defines | `development`, `staging`, `qa`, `production` |
| `docs/` | This documentation | `docs/platform/` is inherited and read-only |

## Request lifecycle

A read, end to end:

```
Widget → Controller → Repository → DataSource → ApiClient
                                                    │
        CookieInterceptor    attach drais_session   │
        SessionInterceptor   watch for a dead session
        RetryInterceptor     idempotent methods only
        LoggingInterceptor   redacted, timed
                                                    ▼
                                            DRAIS backend
                                    getSessionSchoolId() → school_id
                                    requirePermission()  → RBAC
                                                    │
        ApiEnvelope.parse    ◄──────────────────────┘
        ErrorMapper          → typed Failure
                                                    │
Widget ◄ Controller ◄ Repository ◄─── Result<T> ────┘
```

Two properties hold at every step:

- **Nothing throws across a layer boundary.** Repositories return `Result<T>`; a caller cannot forget the failure case, because the compiler rejects an incomplete `switch`.
- **`DioException` never escapes `core/network/`.** Everything above reasons in `Failure`, which is why the transport could be replaced without touching a screen.

## The five things that are not obvious

1. **There is no token refresh, because there is no token.** Authentication is an opaque server-side session behind an `HttpOnly` cookie with a hard seven-day expiry. [M0002](adr/M0002-cookie-session-parity.md).
2. **The client never sends `school_id`.** The server derives it from the session and ignores client input — that is the tenant-isolation guarantee ([ADR-0008](platform/0008-two-auth-systems.md)).
3. **Permission checks decide what to draw, never what is allowed.** The server re-checks every request.
4. **`AuthStatus.offlineUnverified` is not "signed out".** A session that cannot be verified is kept; a teacher with no signal must not be logged out.
5. **Login is two calls.** `/api/auth/login` establishes the session; `/api/auth/me` loads the identity. The login payload's `isSuperAdmin` is computed loosely and must not be trusted — see [PARITY §3.2](PARITY.md).

## Testing

`flutter test` — no server, no device, no code generation.

The seams that make this possible: `domain/` has no dependencies; repositories are typed as interfaces; every dependency is an overridable provider; `AppConfig.test` gives deterministic configuration.

Covered today: permission semantics, envelope parsing, error-code classification, redaction, configuration validation. See [CONTRIBUTING](../CONTRIBUTING.md) for what to test when adding a module.

## Related

- [M0001](adr/M0001-riverpod-as-state-and-di.md) · [M0002](adr/M0002-cookie-session-parity.md) · [M0003](adr/M0003-go-router-navigation.md) · [M0004](adr/M0004-no-business-logic-in-the-client.md) · [M0005](adr/M0005-hand-written-serialization.md)
- [PARITY](PARITY.md) — what is shared, what differs, what is broken upstream
- [ENVIRONMENTS](ENVIRONMENTS.md) · [OFFLINE_STRATEGY](OFFLINE_STRATEGY.md) · [ROADMAP](ROADMAP.md)
- [`docs/platform/`](platform/README.md) — the inherited platform decisions
