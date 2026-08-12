# Offline strategy

## What works offline today, honestly

**Reads that have been loaded before. Nothing else.**

`CacheStore` keeps successful `GET` response bodies. When a read fails for a network reason, the last stored body is served and the UI shows an offline banner. Writes fail with a `NetworkFailure` and are not queued.

That is the whole capability at 1.0.0. It is stated plainly here rather than described as "offline support", because a half-built sync layer that silently loses a morning's attendance is worse than no sync layer at all.

## Why it stops there

DRAIS serves Ugandan schools where connectivity is intermittent and not guaranteed during the school day. Offline writes are a real need, not a nice-to-have — [ADR-0010](platform/0010-dual-database-mode.md) is built around exactly that reality.

The same ADR is equally clear about why the platform has **not** built bidirectional sync:

> Real bidirectional sync is the obvious next want and the reason it hasn't been built is worth recording: it requires a conflict-resolution model for records edited in both places, which is a **substantial design problem, not an implementation gap**.

That reasoning transfers directly. Two staff members marking the same class from two phones, one of them offline, is a conflict the *platform* has to have an opinion about. A mobile-only answer would be an opinion invented by one client — the drift [M0004](adr/M0004-no-business-logic-in-the-client.md) exists to prevent.

There is also a hard blocker: **the internal API has no idempotency mechanism.** Only the external Platform API has one ([ADR-0011](platform/0011-platform-api-contract-freeze.md)). Without idempotency keys, replaying a queued write after reconnection can double it — a duplicated attendance record, a duplicated payment, a guardian SMS sent twice and billed twice. This is also why `RetryInterceptor` never retries `POST`, `PUT`, `PATCH` or `DELETE`.

## What the desktop build does instead, and why a phone cannot

LongTerm's Electron and Android builds run a **real Next.js server locally against a local MySQL** ([ADR-0010](platform/0010-dual-database-mode.md)), which is why they work with no internet at all.

A Flutter phone app cannot and must not do this:

- it would need database credentials in the binary, readable by anyone with the APK;
- it would hold a tenant's data on a device that is lost far more often than a desktop;
- it would need the business rules on the device, which is precisely [M0004](adr/M0004-no-business-logic-in-the-client.md)'s prohibition;
- `isLocalAllowed()` requires `DRAIS_ALLOW_LOCAL=true` server-side — a deliberate opt-in for machines an administrator controls, not consumer handsets.

A phone in a classroom and a school-owned desktop on the LAN are different security propositions. The desktop build remains the answer for genuinely disconnected operation.

## The intended path forward

In order. Each step is useful on its own, and none requires the next.

### Step 1 — Cache reads that matter (no server change)

Extend `cacheFor` to the endpoints where staleness is acceptable and value is high: timetable, class lists, learner profiles, school configuration. Show "last updated" wherever cached data is displayed.

Cheap, safe, and covers a large share of real offline use — most of what staff need on a phone is a lookup.

### Step 2 — Replace the cache backing store

`SharedPreferences` is plaintext and not built for volume. Move to **Drift** (SQLite) with a typed schema and per-entity TTLs.

Two rules survive the move: the store holds **server answers, never inputs to re-derive them**, and it is cleared on sign-out — cached tenant data outliving a session on a shared tablet is a device-side isolation failure even when the server behaved correctly.

### Step 3 — Server-side idempotency (**platform work, and the real blocker**)

Ask LongTerm for idempotency keys on internal write routes: the client sends `Idempotency-Key`, the server stores it with the result, and a replay returns the original outcome instead of acting twice.

The Platform API's implementation is the model. **Nothing in steps 4 or 5 is safe to build before this exists.**

### Step 4 — An outbox of intents

A durable queue of *user intents* — "mark learner 123 present at 07:42 on 2026-08-05" — not of computed state. Each carries an idempotency key and is replayed on reconnection.

The distinction matters: an intent is a fact about what a person did, which the server can evaluate against its own rules. Queued *state* would require the device to have computed something, which is the prohibition again.

Uncommitted intents must be visible in the UI. A teacher must be able to see that eleven marks have not yet reached the server.

### Step 5 — A conflict model (**platform decision, not a mobile one**)

Only once steps 3 and 4 are real, and only as a decision made *for the platform*: which side wins when a record changed in both places, who is told, and how. It belongs in a LongTerm ADR that both surfaces then implement.

## Rules for anyone working on this

1. **Never queue a write without an idempotency key.** Duplicated financial or attendance records are the failure mode.
2. **Never compute business state on the device**, offline or not ([M0004](adr/M0004-no-business-logic-in-the-client.md)).
3. **Never let cached data outlive a session.** `AuthRepositoryImpl` clears the cache on sign-in and sign-out; keep it that way.
4. **Never silently discard an unsent intent.** If it cannot be sent, say so.
5. **Distinguish "offline" from "signed out".** `AuthStatus.offlineUnverified` exists for this; a teacher with no signal keeps their session.
6. **Radio state is a hint, not proof.** `connectivity_plus` reports the radio; a school Wi-Fi with no upstream link reports `wifi` while everything fails. Only `/api/health` proves reachability.

## Related

- [ADR-0010](platform/0010-dual-database-mode.md) — why offline matters, and why sync is unsolved
- [`OFFLINE_MIGRATION_ASSESSMENT.md`](platform/OFFLINE_MIGRATION_ASSESSMENT.md) — the platform's own analysis; prior art for any work here
- [M0004](adr/M0004-no-business-logic-in-the-client.md) · [ROADMAP](ROADMAP.md)
