# Platform parity and observed divergences

This document exists so that DRAIS Mobile and DRAIS LongTerm can be kept in step deliberately rather than by memory.

It records three things:

1. what the mobile app **inherits unchanged** from the platform;
2. where mobile **deliberately differs**, and why that is not drift;
3. **technical debt observed in LongTerm** while building the client, which affects mobile.

`lib/core/constants/app_version.dart` holds `verifiedAgainstLongTerm`. It currently reads **`1.173.45`** — the LongTerm version this audit was performed against. When the platform is re-audited, update that constant, this document, and `docs/platform/`.

---

## 1. Inherited unchanged

| Concern | Source of truth | Mobile expression |
|---|---|---|
| Authentication | `POST /api/auth/login`, `drais_session` cookie, `sessions` table | `CookieStore` + `CookieInterceptor` — the app is a cookie client ([M0002](adr/M0002-cookie-session-parity.md)) |
| Identity | `GET /api/auth/me` | `AuthUserDto` → `AuthUser` |
| Tenant isolation | `getSessionSchoolId()`; server ignores client `school_id` | The app never sends one ([M0004](adr/M0004-no-business-logic-in-the-client.md)) |
| Authorization | `requirePermission()`, `userCan()`, `expandPermissionChain()` | `PermissionSet.allows()` mirrors the wildcard chain exactly — for rendering only |
| Super-admin test | `is_super_admin` **OR** `slug='super_admin'` **OR** name in `('super admin','superadmin')` | `Role.isSuperAdmin` reproduces all three |
| Error vocabulary | `ApiErrorCode` in `src/lib/apiResponse.ts` | `ApiErrorCode` enum, plus the hand-written route codes (see §3.1) |
| Response envelope | `{success, data}` / `{success, message, data}` / flat | `ApiEnvelope.parse` handles all three |
| Attendance Health Score | `computeOverallHealth` + the ten checks in `src/lib/attendance/health.ts` | `features/timehealth/domain/health_report.dart` + `runHealthChecks()` — same checks, weights, bands and ladders; 13 tests pin them |
| School-local dates | `src/lib/datetime/local-date.ts` | `core/datetime/local_date.dart` ([ADR-0004](platform/)) |
| Error-handling standard | `docs/guides/API_ERROR_HANDLING_GUIDE.md` — zero silent failures | `Failure` + `Result`; repositories never throw |
| Pagination | `page`/`limit`, `{data, total, page, limit}` | `PageRequest` / `PagedResult` |
| Subscription gating | `getSubscriptionInfo()`, 402 responses | `SubscriptionStatus` read verbatim; nothing computed locally |
| Session lifetime | 7 days, no sliding renewal | Accepted as-is; no client-side extension attempted |
| Versioning | MAJOR/MINOR/PATCH, conventional commits | Same rules, independent number line ([VERSIONING](VERSIONING.md)) |
| Upload limit | `MAX_FILE_SIZE` = 10 MB | `AppConfig.maxUploadBytes`, checked before upload |
| Currency default | `UGX` | `SchoolSummary.currency` default |

---

## 2. Deliberate mobile differences

Each of these is a presentation-layer decision — the layer the brief exempts from parity — or a platform constraint that has no web equivalent.

| Difference | Web | Mobile | Why |
|---|---|---|---|
| Toasts on mutation | `apiFetch` toasts every mutation | `ApiClient` is silent; controllers decide | The same call may come from a screen, a pull-to-refresh or a background sync. Presentation belongs in the presentation layer. |
| Data layer | SWR ([ADR-0013](platform/0013-swr-as-the-client-data-layer.md)) | Riverpod + explicit cache | No SWR equivalent; the invalidation discipline is mirrored ([M0001](adr/M0001-riverpod-as-state-and-di.md)) |
| Route guards | `middleware.ts` on the server | `go_router` redirect on the device | No server-side middleware exists for a native client ([M0003](adr/M0003-go-router-navigation.md)) |
| Offline | Local MySQL mode for desktop/Android ([ADR-0010](platform/0010-dual-database-mode.md)) | Read-only response cache, **no local database** | A phone must never hold credentials or a tenant database ([OFFLINE_STRATEGY](OFFLINE_STRATEGY.md)) |
| Session storage | Browser cookie jar | Platform keystore | A phone is lost more often than a desktop |
| Theming | Tailwind | Material 3 from a brand seed | No portable mechanism; identity preserved, implementation differs |
| Serialisation | TypeScript interfaces | Hand-written Dart parsers | [M0005](adr/M0005-hand-written-serialization.md) |
| Version number | 1.173.x | 1.7.0 | Mobile's own number line ([VERSIONING](VERSIONING.md)) |
| Health check 9 (`db`) | `SELECT 1` round-trip from a Vercel function | Same probe, from the handset | Direct mode has no server in between. On a phone this is the more honest number — a school on a bad connection genuinely does have a slow database. Same ladder (250 ms / 1000 ms), different distance. |

### Mobile-only logic — no LongTerm counterpart

One piece of derived logic in this codebase was **written here, not transcribed**. It is listed so it can never be mistaken for parity:

| What | Where | Standing |
|---|---|---|
| `AttendanceTrendDay.isUniform` — flags a day where every arrival was classed identically (≥10 arrivals, all present or all late) as a likely clock/shift problem rather than behaviour | `features/attendance/domain/repositories/attendance_repository.dart` | **Kept, and documented in place.** A hint on a chart only: nothing is written back from it and no reported figure depends on it. The authoritative signal for the same condition is the health score's `time` and `device_rep` checks, which *are* transcribed. Delete it if LongTerm grows an equivalent. |

Four other heuristics that were invented locally — a 4-hour silence threshold, a 60-second skew threshold, 50% under-reporting, and a 10-day baseline reliability floor — were **removed in 1.7.0** and replaced by the platform's ten-check score.

### Not implemented, deliberately

- **Control Center** (`/api/control-center/*`, `drais_control`). Permanently out of scope: shipping platform-operator credentials in a consumer app would collapse the boundary [ADR-0008](platform/0008-two-auth-systems.md) exists to protect.
- **Parent portal** (`/api/portal/*`, `/api/parent/*`). A separate identity space with its own OTP flow and isolation gate ([ADR-0009](platform/0009-parent-portal-isolation-gate.md)). A parent app is a **second auth domain**, not a role in this one — see [ROADMAP](ROADMAP.md).
- **Platform API v1** (`/api/platform/v1/*`). For external integrators such as Jeton, scope-authorised by API key ([ADR-0011](platform/0011-platform-api-contract-freeze.md)). Mobile is a first-party client and uses the internal API.
- **Password reset.** No mobile-reachable flow exists server-side; the login screen says so rather than offering a dead link.

---

## 3. Technical debt observed in LongTerm

Found while building the client, at LongTerm 1.173.15. **None is a mobile bug**; each is a platform issue whose cost is now shared by two clients. Ordered by impact on mobile.

### 3.1 Auth routes bypass the standard error envelope — *high*

`src/lib/apiResponse.ts` defines the canonical `ApiErrorCode` enum and calls its `ok()`/`fail()` helpers *"MANDATORY for all new/updated routes"*. `/api/auth/login`, `/api/auth/me` and `/api/auth/logout` use none of it: they hand-build `NextResponse.json` and emit codes that are not in the enum — `INVALID_CREDENTIALS`, `ACCOUNT_PENDING`, `ACCOUNT_INACTIVE`, `SCHOOL_SUSPENDED`, `SCHOOL_INACTIVE`, `SUBSCRIPTION_EXPIRED`, `NOT_AUTHENTICATED`, `LOGOUT_ERROR`.

**Mobile impact:** `ApiErrorCode` must carry both families, and `ErrorMapper` must classify by code *and* by HTTP status. A client written only against the enum would misclassify every login failure.

**Suggested fix:** add the missing codes to the enum and migrate the three routes to `createErrorResponse()`. Additive and non-breaking.

### 3.2 `isSuperAdmin` is computed two different ways — *high, security-adjacent*

`/api/auth/login` derives it by string-matching role names:

```ts
r.name?.toLowerCase().includes('admin') || r.name?.toLowerCase().includes('super')
```

`/api/auth/me` and `src/lib/auth.ts` use the correct three-way test (`is_super_admin` / `slug` / canonical name).

The login version returns `true` for any role whose **name contains "admin"** — "Deputy Admin", "Admissions Officer", "Administrator (Records)" — and then grants `permissions: ['*']` in that response.

**Mobile impact:** the client must ignore the login payload's identity entirely and re-read `/api/auth/me`. It does, and the reason is commented in `AuthRepositoryImpl.login`. A less careful client would render a super-admin interface for an admissions clerk. The server would still refuse the actions, so this is a UI-correctness issue rather than a breach — but it is one string away from being worse.

**Suggested fix:** have `/api/auth/login` call the same helper as the session query, or drop identity from the login response entirely and make `/api/auth/me` the only source.

### 3.3 Three response envelope shapes coexist — *medium*

`createSuccessResponse()` → `{success, data}`; `ok()` → `{success, message, data}`; auth routes → flat `{success, user, setupComplete}`. `apiClient.ts` absorbs this with `data?.data || data`.

**Mobile impact:** `ApiEnvelope.parse` supports all three and callers pass an explicit `dataKey`. Workable, but every new endpoint integration starts by determining which shape it uses.

**Suggested fix:** converge on `ok()`. Adding `data` alongside the existing flat keys would be non-breaking for the web client.

### 3.4 Field naming is inconsistent across responses — *medium*

The same subscription object is `subscription` in the login response and `subscriptionInfo` in `/api/auth/me`. `roles` is an object array in one and a string array in the other.

**Mobile impact:** `ErrorMapper` and `AuthUserDto` check both spellings and both shapes.

### 3.5 A schema migration runs inside the hot session path — *medium*

`src/lib/auth.ts` calls `ensureImpersonationColumn()`, which issues `ALTER TABLE sessions ADD COLUMN …` at runtime, promise-gated and cached, before the session `SELECT`.

The comment explains it honestly — without it, a fresh deploy would reference a missing column and break every login. But a DDL statement on the authentication path means the **first request after every cold start** carries a schema-change attempt, and on serverless that is every cold instance.

**Mobile impact:** occasional slow first requests after a deploy, which the client's timeout and retry configuration absorbs. Worth knowing before blaming the network.

**Suggested fix:** move it to the managed migration runner (`database/migrations/tidb/`), which `docs/database/MIGRATIONS.md` already designates for new work.

### 3.6 No test coverage on routes, RBAC or auth — *medium*

LongTerm's `CONTRIBUTING.md` states it plainly: no coverage of the ~685 API routes, RBAC/auth, the portal isolation gate, the backup orchestrator, the platform API, or the Electron/Capacitor boot paths, and no E2E layer.

**Mobile impact:** the app cannot inherit confidence that does not exist. A backend change can break the client silently. This is the strongest argument for **contract tests** — the same recommendation [ADR-0011](platform/0011-platform-api-contract-freeze.md) makes for the external API, applied to the handful of internal routes mobile depends on.

### 3.7 `JWT_SECRET` / `REFRESH_SECRET` are configured but unused — *low*

Present in `.env.example` and `.env.local`, unused by school auth, which is session-cookie based. Misleading: it invites the assumption that a token flow exists.

**Mobile impact:** none, once understood. It cost audit time and is the reason [M0002](adr/M0002-cookie-session-parity.md) opens by stating what the platform actually does.

**Suggested fix:** remove them, or comment them as reserved.

### 3.8 Role guards in `middleware.ts` compare role *names* — *low*

`ROLE_PROTECTED` matches against the `drais_role` cookie with literal strings: `['Admin', 'Super Admin', 'Bursar']`. Role names are school-editable; slugs are the stable contract, as `src/lib/auth.ts` itself notes.

**Mobile impact:** none today — mobile has no role-gated routes. It matters the moment one is added, and the mobile implementation should gate on **permission codes**, not role names.

### 3.9 `LIMIT ?` incompatibility with TiDB — *informational*

Handled centrally in `query()` ([ADR-0010](platform/0010-dual-database-mode.md)): TiDB rejects bound `LIMIT`/`OFFSET` under the prepared-statement protocol, so those queries route to the text protocol.

**Mobile impact:** none while it holds. Recorded because the regression signature is distinctive and easy to misattribute: **only paginated endpoints fail, and only in production.** A mobile engineer seeing that should look here before debugging the client.

---

## Keeping this document true

- Re-audit on every LongTerm MAJOR or MINOR release, and whenever a mobile integration hits an unexpected response.
- Update `verifiedAgainstLongTerm` in the same commit.
- When a debt item is fixed upstream, strike it here with the version that fixed it — do not delete it. The history of what was wrong is how the next engineer understands why the client is shaped as it is.
