# DRAIS Server

The Dart implementation of the DRAIS API. **No JavaScript anywhere.**

```
Flutter app  ──HTTPS──▶  DRAIS Server (Dart)  ──TLS──▶  TiDB Cloud
```

This is **phase 1 of a strangler migration**: authentication only. The Next.js application still owns the other ~688 routes, and this service is designed to run *beside* it, not in place of it.

## Why it exists, and what it proves

The question was whether DRAIS could be Dart top to bottom. Rather than answer it with an estimate, this implements the smallest surface that exercises every risk — database driver, session model, password compatibility, response contract — for about 1,500 lines instead of 61,000.

Verified against the live TiDB instance:

| Risk | Result |
|---|---|
| Can Dart reach TiDB Cloud over TLS? | **Yes** — 327 ms first query |
| Does the session query (EXISTS subquery, 4 joins) run? | **Yes** — 231 ms |
| Can Dart verify existing password hashes? | **Yes** — Node `bcryptjs` `$2b$` verified from Dart |
| Do existing users need a password reset? | **No** — 37 of 38 rows are `$2b$`, all readable |
| Does the client need changing? | **No** — same cookies, same envelope, same codes |

The password result is the one that mattered. Had it failed, every user would have needed a reset and the migration would have been dead on arrival.

## Running it

```bash
cd server
dart pub get
cp .env.example .env      # fill in TIDB_HOST / TIDB_USER / TIDB_PASSWORD
dart run bin/server.dart
```

```
DRAIS Server starting…
  ✔ TiDB reachable (327ms)
  ✔ Listening on http://0.0.0.0:8080
```

Then open DRAIS Mobile, and on the connect screen enter this machine's address — `192.168.1.50:8080` on a LAN, or `127.0.0.1:8080` on the same machine. **No client code changes.** That is the whole point.

```bash
dart analyze && dart test
```

## Routes

| Route | Mirrors |
|---|---|
| `GET /api/health` | `src/app/api/health/route.ts` |
| `POST /api/auth/login` | `src/app/api/auth/login/route.ts` |
| `GET /api/auth/me` | `src/app/api/auth/me/route.ts` |
| `POST /api/auth/logout` | `src/app/api/auth/logout/route.ts` |

## The contract is not negotiable

Field names, cookie names, status codes and error codes match `src/app/api/auth/*/route.ts` exactly. Where the platform is inconsistent, this **reproduces the inconsistency** — a tidy-up here is a break for every installed app.

Two deliberate exceptions, both marked in the source:

1. **`isSuperAdmin` on login is computed correctly.** LongTerm's login route derives it by matching role *names* against `'admin'`/`'super'`, so a "Deputy Admin" is handed `permissions: ['*']` (`../docs/PARITY.md` §3.2). This uses the same three-way test as the session query. The field keeps its name and type; it just stops being wrong.
2. **A `$2b$` hash is normalised to `$2a$` before verification.** The prefixes are verification-compatible; `dbcrypt` is stricter about prefixes than `bcryptjs`. See `lib/auth/password.dart`.

## Things that will bite you

**TiDB rejects `LIMIT ?`.** Bound `LIMIT`/`OFFSET` fail under the prepared-statement protocol — and *only* against TiDB, *only* in production. `Database.query` throws on such a statement so it fails in development instead; use `Database.limitClause()`.

**`SECURE_COOKIES` must be false on a plain-HTTP LAN.** A `Secure` cookie over HTTP is silently never returned, which presents as "login succeeds, then immediately signed out".

**Sessions do not slide.** `last_activity_at` is touched on each request; `expires_at` is not extended. Seven days is seven days, matching the platform.

**Nothing here belongs in the mobile app.** The credentials in `.env` are the reason this process exists. An APK is a zip file.

## Layout

```
bin/server.dart          entry point, health route, graceful shutdown
lib/config/env.dart      configuration + validation
lib/db/database.dart     TiDB pool, ? → :pN binding, the LIMIT guard
lib/auth/password.dart   bcrypt, cross-compatible with bcryptjs
lib/auth/session.dart    session creation + validation (getSessionSchoolId)
lib/auth/rbac.dart       roles, permissions, wildcard expansion
lib/http/               envelope, cookies, middleware
lib/routes/auth_routes.dart
```

`Rbac.expandChain` must stay identical to `PermissionSet.expandChain` in the Flutter client and `expandPermissionChain` in LongTerm. All three are tested against the same cases; if they disagree, the UI hides functionality the server allows, or offers actions that 403.

## What is not here

Sign-up, password reset, OTP, sessions list, impersonation — and every non-auth route. Migration order is in `../docs/ROADMAP.md`.

**Control Center is deliberately excluded and should stay that way.** It is a separate authentication domain (ADR-0008), and mixing it in would collapse the boundary that keeps platform operations away from school data.

## Honest risks

- **`mysql_client` is 0.0.27.** Pre-1.0, and the least mature link in this stack. Node's `mysql2` has years more production exposure. It works — the numbers above are real — but this deserves load testing before it carries a school day.
- **No transactions yet.** Auth does not need them; finance will.
- **Single process, no clustering.** Fine for one school, insufficient for the hosted deployment.
- **Two implementations now exist.** Until Next.js auth is retired, a change to session handling must land in both. That is the cost of a strangler migration, and it is why the surface was kept small.
