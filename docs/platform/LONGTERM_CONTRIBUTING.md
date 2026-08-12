# Contributing to DRAIS

This is the practical guide to working on DRAIS: setup, tests, database changes, and the commit conventions the tooling depends on.

For *what* DRAIS is, read the [root README](README.md). For *why* it is built the way it is — read before changing any subsystem — read the [Architecture Decision Records](docs/adr/README.md).

## Setup

```bash
npm install                    # also installs git hooks (see "Versioning")
cp .env.example .env.local     # configure DB + secrets
npm run dev                    # http://localhost:3000
```

`npm install` runs `scripts/install-hooks.mjs`, which sets `core.hooksPath` to `.githooks`. If you see `could not set core.hooksPath` during install, run it manually — without it, versions will not bump on commit:

```bash
git config core.hooksPath .githooks
```

### Database modes

DRAIS runs against **TiDB Cloud** (`online`) or **local MySQL** (`local`). See [ADR-0010](docs/adr/0010-dual-database-mode.md) for why both exist.

- Online (default): set `TIDB_HOST`, `TIDB_PORT`, `TIDB_USER`, `TIDB_PASSWORD`, `TIDB_DB`.
- Local: requires `DRAIS_ALLOW_LOCAL=true` **plus** `LOCAL_MYSQL_*`. Without that flag the resolver hard-forces online, whatever else is configured — that is deliberate, so a hosted deployment can never fall into local mode.

```bash
npm run db:local:init      # create + seed a local database
npm run db:local:verify    # check it
```

> **Working against production data:** several scripts and verifiers connect to the live TiDB instance. Read-only checks (`verify:divisions`) are safe. Anything that writes is not — confirm which database you are pointed at before running it.

## Tests

Domain suites, using the Node test runner via `tsx`:

```bash
npm run test:drce           npm run test:snapshots
npm run test:attendance     npm run test:biometric
npm run test:ingestion      npm run test:notifications
npm run test:passouts       npm run test:allocations
```

Non-test gates:

```bash
npm run typecheck           # tsc --noEmit
npm run lint                # eslint
npm run lint:permissions    # every permission code is registered
npm run gate                # phase stability gate
npm run trash:verify        # soft-delete descriptors are coherent
npm run verify:divisions    # aggregate/division coherence, runs against production
```

**Test suites without an npm script.** `src/lib/control/__tests__`, `src/lib/finance/__tests__`, `src/lib/reports/__tests__`, and `src/lib/academics/__tests__` exist but are not wired to a script, so they do not run by default. Run them directly with `npx tsx --test <path>` if you are working in those areas.

**What is not covered.** Tests are pure-function unit tests around the engines. There is no coverage of the ~685 API routes, RBAC/auth, the portal isolation gate, the backup orchestrator, the platform API, or the Electron/Capacitor boot paths, and no E2E layer. Treat changes in those areas as needing manual verification — and say so in the PR rather than implying test coverage that does not exist.

## Database changes

**Three schema mechanisms coexist.** Know which one you are using — see [docs/database/MIGRATIONS.md](docs/database/MIGRATIONS.md) for the full explanation.

For any new work, use the **managed migration runner**:

```bash
# 1. Create database/migrations/tidb/NNN_short_description.sql
# 2. Check what's pending
node --env-file=.env.local scripts/db/migrate.mjs --status
# 3. Dry run, then apply
node --env-file=.env.local scripts/db/migrate.mjs --dry-run
node --env-file=.env.local scripts/db/migrate.mjs
```

Rules:

- **Migrations are additive and idempotent.** Use `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`, `ADD INDEX IF NOT EXISTS`. The runner tolerates duplicate-object error codes on re-run.
- **Never edit an applied migration.** The runner checksums them and aborts on drift. An edit-after-apply is a *new* migration.
- **New tenant tables need `school_id`.** The backup engine and Control Center discover school-owned tables by looking for that column ([ADR-0008](docs/adr/0008-two-auth-systems.md) context); a table without it, and without an FK path to one, is treated as global and excluded from per-school operations.

## Writing API routes

Read [docs/guides/API_ERROR_HANDLING_GUIDE.md](docs/guides/API_ERROR_HANDLING_GUIDE.md) first — the "zero silent failures" standard is mandatory.

Non-negotiables:

- **Derive `school_id` from the session, never from the request body or query.** `getSessionSchoolId(req)` is the only acceptable source on school routes.
- **Gate with `requirePermission(userId, schoolId, code, isSuperAdmin)`**, and register the permission code (`lint:permissions` enforces this).
- **Control Center routes use a different auth system entirely** — `getControlSession` + `canManage`/`controlCan`, audited to `control_audit_logs`. Do not mix the two. See [ADR-0008](docs/adr/0008-two-auth-systems.md).
- **Parent portal routes must go through the isolation gate.** See [ADR-0009](docs/adr/0009-parent-portal-isolation-gate.md) — this is a required code-review check.
- **Audit mutations** via `logAudit()` with an `AuditAction` constant.
- **Paginate list endpoints.** An unbounded query over a large school will time out or exhaust memory.

## Versioning and commits

The version in `package.json` is bumped automatically by the `.githooks/pre-commit` hook. The segment depends on the change type:

| Segment | When |
|---|---|
| MAJOR | breaking change (`feat!:`, `fix!:`, or `BREAKING CHANGE`) |
| MINOR | new feature (`feat:`) |
| PATCH | everything else — default |

**The hook cannot reliably read your commit message** (at pre-commit time, `COMMIT_EDITMSG` still holds the *previous* commit's message, which would misclassify by one). So pass the type explicitly for anything above patch:

```bash
BUMP_TYPE=minor BUMP_MSG="add X" git commit -m "feat(scope): add X"
git tag v1.2.0
git push origin main --tags
```

If `node` is not on `PATH` or the bump script fails, the hook skips the bump rather than blocking the commit — a stale version is preferable to a blocked one.

> **Note on the `origin` remote:** it has two push URLs. The primary succeeds; the secondary may return 403. **A 403 from the secondary is not a failed push** — the commit landed on the primary.

## Documentation

- **Changing behaviour?** Update the subsystem's `README.md` in `src/lib/<subsystem>/`.
- **Making an architectural decision?** Write an ADR — copy [docs/adr/TEMPLATE.md](docs/adr/TEMPLATE.md). "Architectural" means it constrains future work, will look wrong to someone who wasn't there, or trades something away deliberately.
- **Superseding a document?** Mark it in its header and link the replacement. Do not leave it to rot — see [docs/archive/README.md](docs/archive/README.md) for what that costs.
- **In-code docs beat `docs/`** for behaviour. They are closer to the code and more likely to stay true.

## Localization

Every user-facing string must exist in **both** English and Arabic. Use `t('key', 'English fallback')` and add the key to both `src/locales/en.json` and `src/locales/ar.json`. Never hardcode a user-facing string in either language.

The known gap ([docs/localization/PHASE0_AUDIT.md](docs/localization/PHASE0_AUDIT.md)) is not missing dictionary entries — those are ~98% complete — but components that bypass `t()` entirely.

## Before you push

```bash
npm run typecheck && npm run lint && npm run test:<affected-domain>
```

Then check that the docs still match what the code does.
