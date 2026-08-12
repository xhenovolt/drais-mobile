# ADR-0010: TiDB Cloud and local MySQL coexist as first-class runtime modes

- **Status:** Accepted
- **Affects:** `src/lib/db/db-mode.ts`, `src/lib/db/pools.ts`, `src/lib/db.ts`, Electron and Android builds

## Problem

DRAIS serves Ugandan schools where **internet connectivity is intermittent and not guaranteed during the school day**. A cloud-only system stops working when the line drops — and attendance, the most time-sensitive function, happens exactly at the start of the day when a school cannot wait for connectivity to return.

At the same time, the hosted product must be cloud-backed: multi-device access, the parent portal, and platform operations all require a shared database.

Both are real requirements for the same product.

## Context

DRAIS ships to four surfaces from one codebase (web, Electron desktop, Android APK, PWA). The desktop and Android builds run a **real Next.js server locally** — on the desktop it binds `0.0.0.0:3210` so ZKTeco devices on the school LAN can reach it directly. These builds can genuinely run a local MySQL and function with no internet at all.

The hosted deployment cannot: there is no localhost MySQL on Vercel.

So the same code must be able to talk to either database, decided at runtime, without the application layer caring — while making it **impossible** for the hosted deployment to accidentally attempt local mode.

## Decision

Two modes, `online` (TiDB Cloud) and `local` (local MySQL), resolved server-side by `getDbMode()` in `src/lib/db/db-mode.ts`. Pool creation and per-mode caching live in `src/lib/db/pools.ts`; the long-standing `query()` / transaction helpers in `src/lib/db.ts` are unchanged, so **all ~435 call sites are untouched** and online behaviour is identical to before the split.

Three rules make this safe:

**1. Local mode is opt-in per deployment.** `isLocalAllowed()` requires `DRAIS_ALLOW_LOCAL === 'true'`. When it is not set, `getDbMode()` **hard-forces online** and ignores everything else. A hosted deployment cannot be switched to local by any UI action or misconfigured variable.

**2. Mode is server-side runtime state, not env.** The UI chooses; the server resolves. Frontend buttons cannot mutate `process.env` after boot, so the runtime override is a **module-level variable**. This is correct for the single-process desktop build — and on serverless it is irrelevant precisely because local is never allowed there. That reasoning is why an otherwise-suspect pattern (module state in a serverless app) is sound here.

**3. Credentials never leave the server.** Only the mode label and health are exposed.

One TiDB-specific quirk is handled centrally in `query()`: **TiDB rejects `LIMIT ?` / `OFFSET ?` under the prepared-statement protocol** (the bound value is treated as a string, producing "Incorrect arguments to LIMIT"). Queries matching that pattern are routed to the text protocol via `.query()` instead of `.execute()` — still parameterized and safely escaped. Without this, paginated queries fail only on TiDB and only in production.

## Alternatives considered

**Cloud-only.** Rejected: unusable during outages, which is when schools most need attendance to work.

**Local-only with sync.** Considered seriously — it is the classic offline-first design. Rejected as a *primary* architecture because it requires conflict resolution across schools sharing devices and a genuinely hard sync layer, and because the hosted multi-tenant product (parent portal, Control Center) needs a shared database anyway. A local-first design would make those secondary.

**SQLite locally, MySQL in cloud.** Rejected outright: two SQL dialects means every query must work on both, and the schema (255 tables) would need dual maintenance. Using MySQL both sides means the *same* schema and the *same* SQL runs everywhere.

**An abstraction layer / ORM over both.** Unnecessary — TiDB is MySQL-protocol-compatible, so one driver (`mysql2`) serves both. Adding an ORM would be a large migration for no isolation benefit.

## Trade-offs

- **A local deployment is an island.** It has no parent portal, no cross-device access, and its data must be transferred deliberately (see `DESKTOP_LOCAL_TRANSFER.md`). There is no automatic sync — this is the honest limitation of the design.
- **Two configurations to keep working**, and bugs can be mode-specific (the `LIMIT ?` issue is exactly this class).
- **Module-level runtime state** is a pattern that is wrong in most serverless code; it is safe here only because of rule 1, and that coupling must be preserved.
- **Local mode needs MySQL installed and initialized on the school's machine**, which is real deployment work (`scripts/db/local-init.mjs`, `local-verify.mjs`).

## Consequences

- Desktop and Android builds work with no internet.
- Hosted deployments cannot be accidentally pointed at a non-existent local database.
- The same schema and SQL run in both modes, so features do not need per-mode implementations.
- Data movement between modes is an explicit, tooled operation rather than an implicit sync.

## A note on the word "hybrid"

**"Hybrid" is overloaded in this codebase and means three unrelated things.** Disambiguate before assuming:

1. **Attendance marking method** — `method='hybrid'` means a day's record came from both device punches and manual marking.
2. **Grading** — a "hybrid" school in `snapshots/generator.ts` runs more than one grading scheme.
3. **Deployment** — cloud plus local, i.e. this ADR.

## Related systems

- `src/lib/db/db-mode.ts`, `src/lib/db/pools.ts`, `src/lib/db.ts`
- `scripts/db/local-init.mjs`, `local-verify.mjs`, `to-mysql8.mjs`
- [`../OFFLINE_MIGRATION_ASSESSMENT.md`](../OFFLINE_MIGRATION_ASSESSMENT.md)
- [`../guides/DESKTOP_LOCAL_TRANSFER.md`](../guides/DESKTOP_LOCAL_TRANSFER.md)

## Future considerations

Real bidirectional sync is the obvious next want and the reason it hasn't been built is worth recording: it requires a conflict-resolution model for records edited in both places, which is a substantial design problem, not an implementation gap. The Backup Center's per-school export is a deliberate stepping stone toward it.
