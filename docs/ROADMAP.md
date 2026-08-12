# Roadmap

1.0.0 ships **the foundation only** — authentication, transport, error handling, storage, navigation, logging, DI, and a dashboard that proves the vertical slice works. No business module is implemented.

That is deliberate. Modules built on an unproven foundation have to be rebuilt; modules built on this one are mostly DTOs, a repository and screens.

## How to add a module

Every module follows the same steps, in this order:

1. **Read the backend first.** Find its routes under `src/app/api/<module>/`, its library under `src/lib/<module>/`, and its ADRs. Note the response shape, the permission codes it gates on, and its pagination parameters.
2. **Add endpoints** to `lib/core/config/api_endpoints.dart`, mirroring the route paths exactly.
3. **Write `domain/entities/`** — what the feature *is*, with no serialisation.
4. **Write `domain/repositories/`** — the interface the application layer depends on.
5. **Write `data/dtos/`** by hand, commenting each backend quirk and citing the route ([M0005](adr/M0005-hand-written-serialization.md)).
6. **Write `data/datasources/` and `data/repositories/`** — one method per route, `Result<T>` returns, no throwing.
7. **Write `application/`** — a `StateNotifier` plus an immutable state class.
8. **Write `presentation/`** — pages and widgets, gated with `ref.watch(canProvider('<code>'))`.
9. **Register providers** in `lib/core/di/providers.dart`.
10. **Add the route** in `lib/app/router/`.
11. **Test** the DTO parsing and the permission gating at minimum.

**Never reimplement a rule the server owns** ([M0004](adr/M0004-no-business-logic-in-the-client.md)). If a number needs computing, the server computes it.

## Module order, and why

The sequence is chosen by *value on a phone*, not by backend size. Some DRAIS subsystems are large and belong on a desktop.

### 1. Attendance — highest value

`/api/attendance/*` · `src/lib/attendance/` · [ADR-0001](platform/ADR_INDEX.md), [ADR-0002](platform/ADR_INDEX.md), [ADR-0003](platform/ADR_INDEX.md), [ADR-0004](platform/ADR_INDEX.md)

The most time-sensitive function in the platform and the one most obviously suited to a device you carry. Marking happens at the start of the day, in a classroom, standing up.

**Watch for:** device wall-time and timezone-safe dates are the subject of four separate ADRs — attendance dates are *not* naive local dates, and the client must send exactly what the backend expects. `method='hybrid'` here means "device punches plus manual marking", one of three unrelated meanings of "hybrid" in this codebase ([ADR-0010](platform/0010-dual-database-mode.md) lists all three).

**Offline:** this is the module that will demand offline writes. Do not improvise — see [OFFLINE_STRATEGY](OFFLINE_STRATEGY.md).

### 2. Students — foundation for everything else

`/api/students/*`, `/api/learners/*`

Lookup, profile, class and stream. Almost every other module needs a learner picker, so building it early stops it being rebuilt three times.

**Watch for:** pagination is mandatory ([CONTRIBUTING](platform/LONGTERM_CONTRIBUTING.md): *"An unbounded query over a large school will time out"*). Soft deletes mean `deleted_at IS NULL` semantics are already applied server-side — never filter locally.

### 3. Notifications — the reason to open the app

`/api/notifications/*` · `src/lib/notifications/`

Term alerts, deadlines, attendance events. Pairs naturally with push, which is the first genuinely new mobile capability the platform gains.

**Watch for:** push requires FCM/APNs, a device-token registration endpoint that does not exist server-side yet, and a deep-link target per notification type. Plan the server work with the module.

### 4. Finance (read-first) — high value, highest risk

`/api/finance/*` · `src/lib/finance/`, `src/lib/finance-permissions.ts`

Fee balances, receipts, payment history.

**Watch for:** finance has its **own permission layer** on top of RBAC. Start read-only. Recording a payment on a phone needs an idempotency story the internal API does not have — the retry interceptor deliberately never retries writes, and this is the module that explains why.

### 5. Timetable — mostly read, mostly cacheable

`/api/timetable-*`

Excellent offline candidate: a timetable changes rarely and is useful constantly.

### 6. Discipline and Work Plans

`/api/work-plans/*`, `/api/workplans/*` — note **both spellings exist** in the backend; establish which is current before integrating.

### 7. Messaging

`/api/sms/*` · `src/lib/africastalking.ts`

Guardian SMS. Credentialed operations stay server-side; the app composes and requests.

## Explicitly not planned

- **Control Center.** Permanently out of scope ([PARITY §2](PARITY.md)).
- **Report card rendering / DRCE.** A canvas engine with bilingual layout and immutable snapshots ([ADR-0005](platform/ADR_INDEX.md), [ADR-0007](platform/ADR_INDEX.md)). Mobile should fetch the **server-rendered PDF**, never re-implement the engine.
- **Biometric device management.** ZKTeco devices are reached over the school LAN by a local server ([ADR-0010](platform/0010-dual-database-mode.md)). A phone is the wrong host.
- **Bulk import / data migration.** Desktop work.

## Platform work mobile needs

Requests to LongTerm, roughly in order of value:

1. **Contract tests** on the routes mobile depends on. [ADR-0011](platform/0011-platform-api-contract-freeze.md) recommends exactly this for the external API; mobile makes it necessary for part of the internal one. [PARITY §3.6](PARITY.md).
2. **A minimum-client-version response.** The server already receives `X-DRAIS-Client-Version`. [VERSIONING](VERSIONING.md).
3. **Fix `isSuperAdmin` in `/api/auth/login`.** [PARITY §3.2](PARITY.md) — one string away from being a real problem.
4. **Consolidate the error envelope and the auth-route codes.** [PARITY §3.1, §3.3](PARITY.md).
5. **A device-token registration endpoint** for push.
6. **Idempotency keys on internal write routes**, without which offline writes and safe retries cannot be built. This is the single largest blocker to offline capability.

## A parent app is a different application

The parent portal is a **separate identity space** with its own OTP login and isolation gate ([ADR-0009](platform/0009-parent-portal-isolation-gate.md)) — not a role within staff auth.

The right structure is a second Flutter app sharing `lib/core/` as a package: same transport, storage, error handling and logging; a different auth domain and a different feature set. Adding parent auth to this app would put two identity systems in one binary, which is the mistake [ADR-0008](platform/0008-two-auth-systems.md) exists to prevent.

## Foundation follow-ups

Known, contained, and worth doing before the codebase grows:

- **Riverpod 3 / `Notifier`** — mechanical, and cheaper now than after ten controllers exist ([M0001](adr/M0001-riverpod-as-state-and-di.md)).
- **Localisation.** LongTerm requires every user-facing string in **both English and Arabic**; mobile strings are currently English-only in source. Adopt `flutter_localizations` with ARB files sourced from `src/locales/{en,ar}.json`, including RTL layout.
- **Widget and integration tests.** Unit coverage exists; the auth flow deserves an end-to-end test against a fake repository.
- **CI**: `flutter analyze && flutter test` on every push.
- **Crash reporting.** `AppLogger` is the seam; nothing is wired to a backend yet.
