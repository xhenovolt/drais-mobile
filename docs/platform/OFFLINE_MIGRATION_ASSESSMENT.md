# DRAIS Offline-First Migration — Architectural Assessment

> **Status:** Analysis only. No implementation, no migrations, no code changes.
> **Date:** 2026-05-06
> **Audit basis:** 391 API routes, 158 pages, 170 database tables,
> 1,592 `session.schoolId` references, 766 `getPool` / `getConnection`
> call sites, 293 files with `school_id` joins, 464 MySQL date-function
> usages, mysql2 raw-query layer (no ORM), Next.js 15 App Router,
> sessions stored in DB, hardcoded TiDB endpoint,
> 16 schools / 30 users / ~3.6k students currently in production.

---

## Table of contents

1. [Executive verdict](#executive-verdict-read-this-first)
2. [Database coupling analysis](#1-database-coupling-analysis)
3. [Next.js architecture analysis](#2-nextjs-architecture-analysis)
4. [DRCE / report engine analysis](#3-drce--report-engine-analysis)
5. [Offline-first complexity analysis](#4-offline-first-complexity-analysis)
6. [File storage analysis](#5-file-storage-analysis)
7. [Performance analysis](#6-performance-analysis)
8. [Security analysis](#7-security-analysis)
9. [Migration strategy analysis](#8-migration-strategy-analysis)
10. [Phase planning](#9-phase-planning)
11. [Final verdict](#10-final-verdict)

---

## EXECUTIVE VERDICT (read this first)

**Difficulty: 8.5 / 10.** Migration is *technically achievable* but it is a
6–12 month engineering project, not a refactor. The system is *deeper* in
cloud assumptions than its surface suggests. The codebase has zero database
abstraction — 766 raw MySQL call sites — so any "swap SQLite in" path
requires a foundational refactor before any feature work.

**Realistic? Yes — but only via the shared-core / dual-target strategy
described in §8.** The "fork the repo and port each route" path is a death
march; mathematically possible, organizationally unwise.

**Biggest hidden danger:** the assumption that `mysql2` raw queries can be
rewritten to SQLite "find/replace" style. They cannot. ~30% of queries use
MySQL-specific syntax (`ON DUPLICATE KEY UPDATE`, `JSON_OBJECT`,
`GROUP_CONCAT`, `FOR UPDATE`, generated columns, ENUM). Naive porting will
produce silent semantic bugs.

**Biggest architectural weakness:** session-based auth tied to a `sessions`
DB table queried on every request. Offline this becomes either trivial
(single-user kiosk) or a complete redesign (local secure token + optional
cloud sync).

**Biggest strategic opportunity:** the *most recent* subsystems — snapshots,
DRCE, overrides — were designed deterministic and pure. They port to SQLite
with near-zero friction. The migration should *invert* normal sequencing
and start from the top of the stack (newest, purest) downward, not
bottom-up.

**Can DRAIS become a dominant offline-first African school platform?** Yes,
if the team accepts that this is a *new product line*, not a Next.js
refactor. Schools in low-connectivity regions need offline-first; the moat
is real. But it requires Electron + native services, not a PWA shim.

---

## 1. DATABASE COUPLING ANALYSIS

### What I found

- **Zero ORM.** Direct `mysql2/promise` everywhere. `src/lib/db.ts` is a
  singleton pool with hardcoded TiDB Cloud endpoint and *no fallback by
  design* (literal comment: "If TiDB is down, the system FAILS loudly").
- **766 call sites** to `getPool` / `getConnection`.
- **MySQL-specific syntax in production queries:**
  - `ON DUPLICATE KEY UPDATE` — 47 occurrences
  - `JSON_OBJECT` / `JSON_EXTRACT` / `JSON_ARRAYAGG` — 11 occurrences
  - `GROUP_CONCAT` — 6+ occurrences in dashboard / duplicate-detection paths
  - `FOR UPDATE` row-locking — 6 occurrences
  - MySQL date math: `NOW()`, `DATE_SUB`, `INTERVAL`, `DATE_FORMAT` — 464 occurrences
- **Schema features that don't translate cleanly to SQLite:**
  - ENUM columns everywhere (status, lifecycle, template_category)
  - `GENERATED ALWAYS AS … VIRTUAL` (snapshot lifecycle, used for the
    inflight unique key)
  - JSON column type (`payload_json` in `report_card_overrides`,
    `schema_json` in `dvcf_documents`)
  - Foreign keys with `ON DELETE CASCADE` (works in SQLite but FK
    enforcement is per-connection PRAGMA)
  - Composite unique indexes on virtual generated columns (used in
    single-flight snapshot lock)
- **AUTO_INCREMENT** primary keys on virtually every table. UUIDs are used
  in **two places only**: `report_snapshots.snapshot_id` (CHAR(36)) and
  Node `randomUUID()` calls in `src/lib/snapshots/generator.ts`. This is
  catastrophic for sync.
- **Transactions:** 69 places use `beginTransaction`. SQLite supports them
  but with single-writer semantics — concurrency model differs.

### Severity

| Concern | Severity | Why |
|---|---|---|
| No repository / query abstraction | **CRITICAL** | 766 call sites must be touched or routed through a new layer |
| AUTO_INCREMENT identifiers | **CRITICAL** | Cannot merge offline-edited data without ID-space conflicts |
| `ON DUPLICATE KEY UPDATE` proliferation | **HIGH** | SQLite has `INSERT … ON CONFLICT` but syntax differs |
| `GROUP_CONCAT` + `JSON_*` functions | **HIGH** | SQLite has equivalents but argument order and NULL semantics differ subtly |
| `FOR UPDATE` locks | **MEDIUM** | SQLite uses WAL + serialized writes; locks are implicit, not explicit |
| Generated virtual columns indexed | **MEDIUM** | SQLite supports generated columns since 3.31 but has stricter indexing rules |
| ENUM | **LOW** | Easy CHECK constraint on SQLite |
| JSON column | **LOW** | SQLite has JSON1 extension built into modern builds |

### SQLite compatibility score: **5.5 / 10**

Every query needs review. ~50% port verbatim, ~30% need rewriting, ~20%
need restructuring (`GROUP_CONCAT`, locking semantics, date math). Without
an abstraction layer, this is touched-by-hand work across 766 sites.

### Recommended abstraction strategy

1. **Adopt Kysely** (preferred over Drizzle for this codebase). Reasons:
   - Type-safe query builder, no schema-migration framework lock-in
   - Native SQLite + MySQL dialects with shared query API
   - Zero runtime dependencies, lighter than Prisma
   - Migration can be incremental — Kysely and raw mysql2 can coexist
2. **Introduce a `RepositoryRegistry`** — a thin per-table interface that
   has *two implementations* (TiDB and SQLite). Snapshots, DRCE registry,
   overrides, schools, students etc. each get a repo. This gives a clean
   boundary without a 766-site big-bang rewrite.
3. **Defer the rewrite of "leaf" queries** (one-off dashboard SQL) to last;
   rewrite the high-traffic write paths first (results, attendance,
   students, snapshots).

---

## 2. NEXT.JS ARCHITECTURE ANALYSIS

### What survives Electron

| Pattern | Status | Notes |
|---|---|---|
| Client components (most pages) | ✅ Direct port | 158 page files, vast majority CSR. Render fine in any browser/webview |
| API routes (`src/app/api/**/route.ts`) | ✅ With caveat | 391 routes — Electron can host the Next.js API as a localhost server |
| `mysql2` driver | ✅ Works in Node main | But you're not using mysql2 offline; this is the layer being replaced |
| `bcryptjs` / `bcrypt` | ✅ Direct port | Native bcrypt may need rebuild for Electron's Node version |
| `socket.io` | ⚠️ Possible | Can run on the local Electron Node main process binding to 127.0.0.1 |
| `next-pwa` | ✅ Already configured | Useful for service-worker shell, but PWA ≠ offline-first; insufficient by itself |
| `@tanstack/react-query` + SWR | ✅ Direct port | Fine, but cache strategy needs rethinking offline |
| `node-zklib` | ✅ Better offline | Currently runs server-side; in Electron it can talk directly to LAN biometric devices without a relay |

### What breaks

| Pattern | Severity | Notes |
|---|---|---|
| **`puppeteer` for server PDF generation** | HIGH | Bundles full Chromium. In Electron use the *built-in* Chromium via `webContents.printToPDF()` — better, but every puppeteer call site must be rewritten |
| **`cloudinary`** for photo upload | HIGH | Cloud-only. Offline replacement = local filesystem with a sync queue when connected |
| **`africastalking`** for SMS | MEDIUM | Cloud-only. Offline = queue + retry when online; impossible without cloud connectivity entirely |
| **`/api/zk-handler` rewrite from `/iclock/:path*`** | MEDIUM | ZKTeco push protocol expects an HTTP server. Electron app must expose this on a known LAN port |
| **`next-auth`** | LOW | Used in only 1 file (`tahfiz/init`); the real auth is custom session-cookie. Easy to strip |
| **Next.js streaming responses** | LOW | A few routes (zk-tcp, attendance/stream) — replace with WebSocket or SSE on the local server |
| **Vercel-specific build (`output: 'standalone'`)** | LOW | Trivially changeable |
| **`X-Frame-Options` + middleware** | LOW | Browser-level; Electron's `BrowserWindow` ignores most of these by default |
| **`process.env` patterns** | LOW | Electron uses `app.getPath()` for user data; env vars become user-config |

### What requires rethinking

- **Session model.** The `sessions` table query runs on every authenticated
  request. On a single-user device this is wasteful and conceptually wrong.
  Offline → either kiosk-mode no-auth, or a local OS-keystore-backed token.
  This is a *design decision*, not just a port.
- **Multi-tenant `school_id` filtering.** 1,592 references. On a desktop
  install, `school_id` is *constant*. The filtering logic still works
  (it's just `WHERE school_id = 8002` always) but the entire conceptual
  model of "many tenants on one DB" is wrong for Electron. Either accept
  the dead weight or refactor 1,592 sites. **Recommendation: leave it
  alone**; treat `school_id` as a single-value constant on the device.
- **Server-side rendering paths.** Most pages are `'use client'` so SSR is
  light. But streaming routes and any `revalidatePath` calls (a handful
  exist) presume a Next.js server. Electron's local Next.js server does
  support these — it just runs on `localhost:PORT` instead of Vercel.
- **Edge runtime:** zero usage detected. **This is a huge positive** —
  every route is Node-runtime-compatible.

### Verdict

**The Next.js layer is more portable than expected.** The hard problem
isn't Next.js — it's the database, the cloud SaaS dependencies (Cloudinary,
Africa's Talking), and the *biometric device protocol layer* that needs a
local HTTP host.

---

## 3. DRCE / REPORT ENGINE ANALYSIS

### Current state (good news)

- **Templates are JSON.** `dvcf_documents.schema_json` is a structured
  DRCEDocument blob. **Portable as-is.**
- **Built-in templates are typed constants** (`BUILT_IN_TEMPLATES` in
  `src/lib/drce/registry.ts`). Portable.
- **Static HTML emergency templates** live in `backup/`. Portable as files.
- **The recently-shipped Phase 2 + 3.1 + 3.2 work is already deterministic
  and pure:**
  - `applyOverrides()` is a pure reducer — zero I/O
  - `snapshotToDRCEDataContext()` is a pure function
  - `snapshotToTemplateMap()` is a pure function
  - The five-layer render pipeline (`RENDER_LAYERS.md`) is documented and
    enforced
- **Snapshots are deterministic** — `meta.dataHash` is sha256 of
  canonical-JSON of `classes`. Same snapshot + same overrides =
  byte-identical output.
- **Snapshot meta v2 freezes branding at generation time** — no runtime DB
  lookup during render. Already offline-friendly.
- **Snapshot generation reads from one big query then computes in-memory.**
  No streaming, no joins per row. Will run against SQLite identically.

### Problems

- **`puppeteer` for PDF.** Used in `src/app/api/students/full/route.ts:410`.
  Server-side Chromium launch. In Electron use `webContents.printToPDF()`
  — different API entirely. **This is the biggest DRCE-adjacent migration
  cost.** Every PDF export path needs rewiring.
- **Snapshot UUID generation uses `node:crypto`** — works in Electron Node
  main process, but if any of this runs in the renderer process you'll hit
  a polyfill issue. Currently server-only, so fine.
- **The registry endpoint reads `dvcf_documents` from DB** — that's a
  query, not a file read. Offline equivalent works the same against SQLite.
- **Print route reads template files from disk**
  (`fs.readFile(path.join(process.cwd(), 'backup', …))`). `process.cwd()`
  becomes problematic in packaged Electron apps — must use
  `app.getAppPath()` or bundle as `app.asar`.

### How DRCE should evolve

1. **Extract `src/lib/drce/*` and `src/lib/snapshots/*` into a shared
   package** (`@drais/report-engine`). Already a logical unit. Pure
   functions. Zero DB dependency at runtime once snapshot meta + overrides
   are loaded.
2. **Move PDF generation to the Electron main process** using
   `webContents.printToPDF()`. Cloud build keeps puppeteer.
3. **Treat the snapshot as a portable artifact** — a school could
   `.drais-snapshot` file-export a snapshot, email it, import it
   elsewhere, and the report renders identically. The architecture already
   supports this; productize it.
4. **Push more rendering into pure functions.** Currently
   `DRCEDocumentRenderer` is a React tree. Consider a *renderer-agnostic*
   representation (the document JSON already is one) with a
   `renderToHTML(doc, ctx, overrides)` helper for headless usage.

### DRCE migration risk: **LOW.** This subsystem is the *poster child* for what offline-first looks like.

---

## 4. OFFLINE-FIRST COMPLEXITY ANALYSIS

### Module-by-module sync risk

| Module | Mutation rate | Conflict risk | Sync strategy |
|---|---|---|---|
| **`students` / `people`** | Medium | **HIGH** — same admission_no entered on two devices | Last-write-wins is wrong; need merge UI for collisions |
| **`results` / `class_results`** (16k+ rows) | High | **HIGH** — same student × subject edited offline by different teachers | Per-cell timestamping + conflict log |
| **`attendance` (zk_*_logs)** | Very high (12k+ rows) | LOW — append-only event stream | Trivial: replay-and-dedupe by composite key (device_id, timestamp, user_id) |
| **`audit_logs` / `system_logs`** | Very high | None — append-only | Trivial: just merge |
| **`schools` config** | Low | LOW — admin-only | Last-write-wins acceptable |
| **`dvcf_documents`** (templates) | Low | LOW — admin-edited | Last-write-wins; document version field already exists |
| **`report_snapshots`** | Low (frozen once ready) | None — UUIDs, immutable after status='ready' | Snapshots are append-only and deterministic; perfect for sync |
| **`report_card_overrides`** | Medium | MEDIUM | Snapshot-bound; conflict only if same (snapshot, student, kind, target) edited on two devices simultaneously |
| **`sessions`** | Very high | None — local only | Don't sync. Each device has its own |
| **`enrollments` / `enrollment_history`** | Medium | MEDIUM — student moved between classes on two devices | Needs conflict resolution UI |
| **`promotions`** | Low (term-bounded) | LOW | Last-write-wins on (student, term) |
| **`exams`, `terms`, `subjects`, `classes`** | Low | LOW | Cloud-authoritative; pull-only on device |
| **`notifications`** | Medium | None — append-only | Trivial merge |
| **`payroll` / `finance`** | Low-Medium | **HIGH** — financial integrity matters | Likely cloud-authoritative; offline read-only |
| **`biometric_devices`, `device_user_mappings`** | Medium | LOW — devices are physical; tied to a single device's LAN | Per-device authoritative |

### Observations

1. **The high-volume tables (`zk_*_logs`, `audit_logs`, `system_logs`) are
   all append-only.** This is *the perfect case* for offline-first sync.
   Use a Lamport timestamp or vector clock for ordering, and merge is
   trivial.
2. **The medium-volume mutating tables (`results`, `class_results`,
   `students`) are the war zone.** Two teachers editing the same student's
   marks on two devices needs *explicit conflict resolution* —
   last-write-wins will silently destroy data. This will need UX, not just
   engineering.
3. **Financial and grading data should not silently merge.** Payroll, fees,
   results that have been published to parents — these need *signed*,
   *append-only* event logs with explicit conflict UIs.
4. **Reference data (terms, classes, subjects, exams)** should be
   cloud-authoritative. Devices pull, never push, for these. Avoids 95% of
   conflict scenarios.

### Sync architecture requirements

- **Per-row monotonic version (vector clock or hybrid logical clock).** A
  `version` integer column or a `last_modified_at` +
  `last_modified_device_id` pair. Currently absent.
- **Conflict log table** to record every merge decision. Auditable.
- **A `sync_queue` table** for pending uploads when offline. Easy to add.
- **Tombstones for deletes.** A `deleted_at` column (some tables have this
  — `schools.deleted_at`, but it's not universal). Hard deletes break sync.
- **Retry + exponential backoff.** Network is unreliable; always assume
  the next push will fail.
- **Idempotent server endpoints.** Currently endpoints assume a single
  source of truth. Sync needs server endpoints to accept
  `(device_id, client_op_id)` and dedupe.

### Existing sync infrastructure

You **already have** `/api/sync/manual-upload`, `/api/sync/trigger-adms`,
`/api/sync/trigger-local`. This is for ZK biometric data syncing. The
pattern exists but is point-solution — needs generalization.

---

## 5. FILE STORAGE ANALYSIS

### What's where

- **Cloudinary** is the primary store for student photos. 7+ files import
  `uploadStudentPhoto`. URLs are persisted in `students.photo_url` as
  `https://res.cloudinary.com/...`.
- **`public/uploads/`, `public/admissions/`, `public/client_logos/`** exist
  locally — used for some assets, school logos, etc.
- **School logos** sit in `public/client_logos/`. Static, deployed with
  the build. Bad for multi-tenant; great for offline.
- **Report assets** (badges, photos) reference filesystem paths in legacy
  emergency templates (e.g. `/albayan-Photoroom1.png`).

### Offline strategy

1. **Primary store: local filesystem** under
   `app.getPath('userData')/<school_id>/photos/<student_id>.jpg`. Files
   keyed by stable IDs (use UUIDs, not auto-increment).
2. **Content-addressable storage** for assets that can change: store as
   `<sha256>.jpg`, keep a `file_assets` table mapping logical name → hash.
   This makes sync trivial (sync = "do we have this hash? no → fetch").
3. **Compression:** stop storing 4MB photos at full resolution. Resize on
   import to a max dimension (1024px), JPEG q=80. ~150KB per photo. 5,000
   students = 750MB. Acceptable.
4. **Sync engine:** when online, compare local file hashes against cloud
   manifest, push deltas, pull deltas. Rsync-style.
5. **Cache:** the renderer should accept `file://` URIs in Electron.
   Replace `https://res.cloudinary.com/...` paths with
   `app://photos/<id>` (Electron protocol handler).
6. **File integrity:** sha256 manifest, periodic verification, repair from
   cloud on mismatch. Catches disk corruption.

### Risk: **MEDIUM.** Solvable but pervasive — every photo URL in the codebase needs to flow through a path-resolver helper, not a hardcoded `https://` assumption.

---

## 6. PERFORMANCE ANALYSIS

### What I observed

- **Largest live tables:** `class_results` 17k rows, `results` 16k,
  `zk_device_logs` 12k. **Trivial for SQLite** — these are table sizes
  that fit entirely in OS page cache.
- **Per-school footprint estimate:** ~10k students max realistic, ~50k
  results per term, ~200k attendance events per year. At maximum a single
  school's data is ~50–100MB SQLite file. Comfortable.
- **Snapshot generation:** reads one big SQL query, processes in memory.
  The current implementation in `src/lib/snapshots/generator.ts` runs
  through `fetchResultsForGeneration` (one query) then iterates. Profile
  against TiDB likely 2–8s for a full school. SQLite will be **faster**
  (no network round-trip).
- **Heavy operations:**
  - PDF generation (puppeteer) — can spike to 1–3 GB RAM. **Replace with
    Electron `printToPDF`** which is far cheaper.
  - `html2canvas` is in deps — used somewhere for screenshot exports;
    runs in browser, fine.
  - `xlsx` parsing for bulk imports — fine.
  - Snapshot regeneration — bound by data volume, deterministic,
    predictable.

### Offline performance expectations

- **Reads will be faster** (10x for cold queries). No network latency.
  Index lookups in microseconds.
- **Writes will be ~equivalent** unless you exceed ~1k inserts/sec
  sustained, at which point WAL checkpointing becomes the bottleneck.
- **Concurrent writes from multiple browser tabs to the same SQLite file:**
  SQLite serializes writers globally. With WAL mode this is fine for
  single-user. Don't do multi-process writes.
- **Memory:** SQLite's default is conservative. A 100MB SQLite file in
  cache mode will use ~50MB RAM. Acceptable.
- **Printing:** PDF generation is the single largest perf risk. Bulk-print
  200 reports → 200 × `webContents.printToPDF()` is doable but slow
  (~30s–2min). Need a worker queue.

### SQLite scaling expectations

- Up to ~10GB single file: comfortable
- 100GB+: requires partitioning or migration to a server DB
- DRAIS is nowhere near this. **No scaling concerns for the foreseeable future.**

### Browser limitations (in Electron)

- IndexedDB / localStorage are still capped, but irrelevant — Electron has
  full Node access
- Can host a real HTTP server on `127.0.0.1:PORT` for the Next.js API
- Can host a *separate* HTTP server on the LAN for ZKTeco device push
  (ICLOCK protocol)
- File access unrestricted via Node fs

### Verdict: **performance is the easy problem.** Worry about correctness, not speed.

---

## 7. SECURITY ANALYSIS

### Current model

- Session cookie (`drais_session`) → DB lookup on every request → derives `school_id`
- bcrypt password hashing
- Permission system (`permissions`, `role_permissions`, `user_roles` tables)
- School-scoped multi-tenant via `WHERE school_id = ?` on every query

### What changes offline

| Concern | Online | Offline | Risk |
|---|---|---|---|
| **Session storage** | DB-backed cookie | Local OS keychain or encrypted file | LOW if done right |
| **Password verification** | bcrypt vs DB hash | bcrypt vs local SQLite hash | LOW — bcrypt works locally |
| **School isolation** | `school_id` filter prevents cross-tenant access | Single-school per device → no cross-tenant problem | **MIGRATES TO ZERO** |
| **Database access** | Behind TLS to TiDB | Local file with OS file permissions | **NEW RISK** |
| **Data at rest** | Managed by TiDB | Plaintext SQLite file | **NEW RISK** |
| **Device theft** | Server retains data | Stolen laptop = stolen DB | **NEW RISK** |
| **Roles/permissions** | Centralized | Local copy, can be tampered with by malicious user | MEDIUM |
| **Audit logs** | Server-resident | Can be edited locally by sufficiently determined adversary | MEDIUM |

### Required offline security work

1. **Database encryption.** SQLCipher (open-source,
   `better-sqlite3`-compatible build) — encrypts the SQLite file. Key
   derived from user password via Argon2. **Mandatory** for any school
   storing identifiable student data.
2. **OS keychain integration.** macOS Keychain, Windows Credential Vault,
   Linux Secret Service. Electron's `safeStorage` API wraps this. Store
   database key, never write it to disk in plaintext.
3. **Tamper-evident audit log.** Hash-chained log entries. If an adversary
   edits an old entry, the chain breaks and you can detect it on next
   sync.
4. **Code signing.** Electron app must be signed (Apple notarization,
   Windows Authenticode) to prevent tampered binaries.
5. **Auto-update with signature verification** (Electron's `autoUpdater`).
6. **Local rate limits / lockout.** Brute-force protection becomes purely
   client-side. Easy to bypass; not your real defense.

### Security migration risk: **MEDIUM-HIGH.** Doable, but the threat model fundamentally changes from "trust the server" to "trust nothing on the client." Expect 4–8 weeks of work just on this layer.

---

## 8. MIGRATION STRATEGY ANALYSIS

### The strategic choice (this is THE decision)

There are four viable architectures. Three are wrong for this project.

#### Option A — Fork the repo. Maintain two codebases.

**Verdict: WRONG.** You will have two divergent systems within 6 months.
Bug fixes won't ship to both. Features will ship to whichever one the dev
was last touching. This is the path most teams choose and most teams
regret.

#### Option B — PWA-only offline (service worker + IndexedDB).

**Verdict: WRONG.** IndexedDB is unsuitable for the SQL workload here (170
tables, complex joins, transactions). Workbox-style cache-first PWA gives
you offline *reads* of *cached* pages. That is not offline-first; that is
degraded-online. ZKTeco devices need a real HTTP server which a PWA cannot
host. SMS queue, file storage, all subpar.

#### Option C — Single Next.js codebase that detects "Electron mode" at runtime.

**Verdict: PARTIALLY RIGHT.** Tempting. Looks clean. But every API route
then needs `if (mode === 'electron') sqlite else mysql` branching. The
cognitive cost compounds. *Some* code will run only in one mode (sync
engine = Electron-only; SMS sender = cloud-only). The branching becomes
the dominant complexity in 12 months.

#### Option D — Monorepo with shared core packages and two thin runtimes. ✅

**Verdict: CORRECT.**

```
drais/
├── packages/
│   ├── @drais/domain          ← Pure business logic (snapshots, DRCE, overrides, ranker, normalizers, grader, registry, render layers). ZERO DB dependency. All pure functions.
│   ├── @drais/repo-contract   ← Repository interfaces (StudentRepo, ResultRepo, SnapshotRepo, etc). TypeScript types only.
│   ├── @drais/repo-mysql      ← TiDB implementation of every repo. Used by cloud.
│   ├── @drais/repo-sqlite     ← SQLite implementation. Used by Electron.
│   ├── @drais/sync-engine     ← Bidirectional sync (Electron ↔ cloud). Used by Electron only.
│   ├── @drais/file-store      ← Local FS + Cloudinary backends behind a common interface.
│   ├── @drais/ui              ← Shared React components (DRCEDocumentRenderer, OverridesPanel, all sections).
│   └── @drais/api-handlers    ← The 391 route handlers, parameterized by repo registry. One implementation, two host environments.
├── apps/
│   ├── cloud/                 ← Next.js app that imports @drais/api-handlers + @drais/repo-mysql. Deploys to Vercel.
│   └── desktop/               ← Electron app that bundles a Next.js server importing @drais/api-handlers + @drais/repo-sqlite + @drais/sync-engine. Same UI, different repos.
└── infra/
    └── …
```

### Why D wins

- **One source of truth for domain logic.** A bug in ranking is fixed
  once.
- **Repository pattern formalizes the abstraction** that's currently
  absent. The 766 raw-SQL call sites become repository method calls —
  typed, testable, dialect-agnostic.
- **Sync engine is a *single* package**, not scattered branches across
  routes.
- **The cloud build keeps shipping while the desktop build is being
  built.** No big-bang switch.
- **Each layer is independently testable.** Domain is pure. Repos are
  mockable. Sync is unit-testable end-to-end.
- **A new dialect (Postgres? Turso?) costs one new package, not a fork.**

### Boundaries that must hold

| Layer | May depend on | May NOT depend on |
|---|---|---|
| `@drais/domain` | nothing (just TS types) | DB drivers, FS, network, browser APIs |
| `@drais/repo-contract` | `@drais/domain` types | any DB driver |
| `@drais/repo-mysql` | mysql2, repo-contract | sqlite, browser |
| `@drais/repo-sqlite` | better-sqlite3, repo-contract | mysql, network |
| `@drais/sync-engine` | both repo packages, network | UI |
| `@drais/api-handlers` | repo-contract, domain | any concrete repo |
| `@drais/ui` | domain types | any DB driver |
| `apps/cloud` | api-handlers, repo-mysql, ui | repo-sqlite, sync-engine |
| `apps/desktop` | api-handlers, repo-sqlite, repo-mysql (for sync), sync-engine, ui | nothing forbidden |

These boundaries are enforced via `tsconfig` paths + ESLint rules.
Violations fail CI.

---

## 9. PHASE PLANNING

Twelve phases. Sequenced for **continuous delivery** — cloud product never
breaks, desktop product builds in parallel. Each phase is demoable.

### PHASE 0 — Engineering foundation (4–6 weeks)

- **Goal:** Establish the monorepo, the repository abstraction, and the
  test harness. **No SQLite yet. No Electron yet.**
- **Scope:** Convert the repo to a pnpm/turbo monorepo. Extract
  `@drais/domain` (snapshots/DRCE/overrides — already pure). Extract
  `@drais/repo-contract`. Implement `@drais/repo-mysql` for the **first
  5 tables** (schools, students, classes, subjects, results). Cloud app
  starts importing them.
- **Risk:** LOW. No behavior change. CI green throughout.
- **Complexity:** 5 / 10 — mechanical but pervasive.
- **Dependencies:** None.
- **Blockers expected:** Workspace tooling friction, build-graph cycles.
- **Testing:** Existing flows, plus new unit tests on the repo interfaces.
- **Rollback:** `git revert`. Cloud product unchanged.

### PHASE 1 — Repository expansion (8–10 weeks)

- **Goal:** Every API route uses a repo, not raw `mysql2`.
- **Scope:** Migrate the remaining ~160 tables × ~391 routes to flow
  through `@drais/repo-contract`. Drive the rewrite by traffic volume —
  high-touch first (results, attendance, students, snapshots, dashboard).
- **Risk:** MEDIUM. Subtle MySQL semantics may leak through.
- **Complexity:** 8 / 10. This is the slog.
- **Dependencies:** Phase 0.
- **Blockers:** `GROUP_CONCAT`, `JSON_OBJECT`, `FOR UPDATE` semantics —
  every occurrence must be reviewed.
- **Testing:** Snapshot-test every endpoint; record current responses,
  compare against post-migration responses.
- **Rollback:** Per-route. Repo is pluggable.

### PHASE 2 — UUIDs + sync metadata schema (3–4 weeks)

- **Goal:** Every sync-eligible row has a stable UUID and a versioning
  column. Cloud DB only — desktop doesn't exist yet.
- **Scope:** Add `external_uuid CHAR(36)`, `version BIGINT`,
  `last_modified_at`, `last_modified_device_id` to the ~30 sync-eligible
  tables. Backfill existing rows with `UUID()`. Make UUIDs the *external*
  identity (URLs, exports), keep AUTO_INCREMENT as internal PK.
- **Risk:** MEDIUM. Schema migration on production data.
- **Complexity:** 6 / 10.
- **Dependencies:** Phase 1.
- **Blockers:** Existing FK relationships use auto-increment PKs.
- **Testing:** Migration dry-run on production-size dataset.
- **Rollback:** Drop columns. UUIDs are additive.

### PHASE 3 — `@drais/repo-sqlite` (8–10 weeks)

- **Goal:** Implement every repo against SQLite using `better-sqlite3` +
  SQLCipher.
- **Scope:** Mirror schema (using SQL with SQLite-compatible types).
  Implement same repo interfaces. Pass the same test suite.
- **Risk:** MEDIUM. Date math, JSON functions, ON CONFLICT semantics
  differ.
- **Complexity:** 7 / 10.
- **Dependencies:** Phase 1 (the repo contract must exist).
- **Blockers:** SQLite generated columns, virtual unique indexes (used in
  snapshot lock — needs a redesign for SQLite).
- **Testing:** Run *every* repo test against both backends. CI green on
  both.
- **Rollback:** Package is unused until Phase 4 picks it up.

### PHASE 4 — Electron shell (4 weeks)

- **Goal:** A desktop binary that boots, runs the Next.js server on
  `localhost`, opens a window, runs against an empty SQLite. Login works.
- **Scope:** Electron main process bootstraps Next.js. Window loads
  `localhost:PORT`. SQLCipher key flow via `safeStorage`. Install/onboard
  wizard creates initial school, admin user, password.
- **Risk:** MEDIUM. Native module rebuilds, code-signing setup.
- **Complexity:** 6 / 10.
- **Dependencies:** Phase 3.
- **Blockers:** `better-sqlite3` native rebuild for Electron's Node
  version. macOS notarization. Windows code-signing certs.
- **Testing:** Cold-boot timing, install/uninstall on Windows + macOS +
  Linux.
- **Rollback:** N/A — new product line.

### PHASE 5 — Local file store + biometric daemon (4–6 weeks)

- **Goal:** Photos work offline. ZKTeco devices push attendance to the
  local Electron-hosted endpoint.
- **Scope:** `@drais/file-store` with local + Cloudinary backends behind
  one interface. Custom protocol handler `app://photos/<uuid>`. Bind
  biometric webhook server on configurable LAN port. Replace
  `puppeteer.launch` with `BrowserWindow.printToPDF()`.
- **Risk:** MEDIUM. Network firewall surprises.
- **Complexity:** 6 / 10.
- **Dependencies:** Phase 4.
- **Blockers:** Customer LAN configurations vary; mDNS / static IP /
  port-conflict edge cases.
- **Testing:** Real biometric devices on real LANs.

### PHASE 6 — Sync engine v1 (one-way, cloud → device) (4 weeks)

- **Goal:** A device can pull a school's data from cloud and stay current.
  No upload yet.
- **Scope:** `@drais/sync-engine` polls cloud `/api/sync/manifest`,
  reconciles by UUID + version. Append-only tables (audit, attendance)
  merge trivially. Reference data (terms, classes, subjects) replaces
  local. Tombstones for deletes.
- **Risk:** LOW. Read-only sync.
- **Complexity:** 6 / 10.
- **Dependencies:** Phase 2 (UUIDs + version columns), Phase 4.
- **Blockers:** Inconsistent data between cloud and device on first sync —
  needs a "wipe and refetch" reset.
- **Testing:** Disconnected → connected → sync → verify equivalence.

### PHASE 7 — Sync engine v2 (bidirectional, with conflict UX) (8–10 weeks)

- **Goal:** Edits made offline propagate to cloud, with explicit UI for
  conflicts on contested rows.
- **Scope:** Local sync queue, retry/backoff, conflict-detection on push,
  conflict-resolution UI for the medium-risk tables (results, students,
  enrollments).
- **Risk:** **HIGH.** This is where data-loss bugs live.
- **Complexity:** 9 / 10. Hardest phase by far.
- **Dependencies:** Phase 6.
- **Blockers:** Concurrent edits on the same student's marks across two
  devices. Financial integrity. Audit-log fork detection.
- **Testing:** Property-based tests with simulated multi-device divergence.
  Chaos testing with random network failures.
- **Rollback:** **NO TRUE ROLLBACK ONCE LIVE.** Once user data is touching
  the sync engine in production, you own the conflict-resolution forever.
  Plan accordingly.

### PHASE 8 — DRCE/snapshot offline parity (2 weeks)

- **Goal:** Snapshot generation, override editing, report rendering, PDF
  export — all work offline.
- **Scope:** Verify every render-layer pure function works against
  SQLite-fetched snapshots. Replace puppeteer everywhere. Local font
  bundling.
- **Risk:** LOW. The architecture is already deterministic.
- **Complexity:** 4 / 10.
- **Dependencies:** Phase 4, 5.

### PHASE 9 — Photo, asset, document sync (4 weeks)

- **Goal:** Binary assets sync between device and cloud,
  content-addressable.
- **Scope:** sha256-keyed object store on both ends. Manifest API. Lazy
  fetch with placeholder UI when missing.
- **Risk:** MEDIUM. Bandwidth, partial transfers, disk space.
- **Complexity:** 6 / 10.
- **Dependencies:** Phase 5, 6.

### PHASE 10 — SMS, notifications, external integrations (3 weeks)

- **Goal:** Africa's Talking, email, push notifications work in both modes.
- **Scope:** Outbound queue on device. Send when online. Idempotency keys
  to prevent duplicates after sync.
- **Risk:** MEDIUM. Duplicate SMS to parents = bad outcome.
- **Complexity:** 5 / 10.

### PHASE 11 — Hardening, perf, security audit (4–6 weeks)

- **Goal:** Production-ready desktop product.
- **Scope:** Penetration test, load test (5k students × 50k results),
  backup/restore UX, auto-update, crash reporting (Sentry-electron).
- **Risk:** LOW.
- **Complexity:** 5 / 10.

### PHASE 12 — General availability (2 weeks)

- **Goal:** Ship.
- **Scope:** Documentation, training videos, installer signing, customer
  onboarding flow.

### Total realistic timeline

**12–18 months** with 2–3 senior engineers. **18–24 months** with one
engineer. There is no compressing this without dropping scope.

---

## 10. FINAL VERDICT

| Question | Answer |
|---|---|
| **Overall difficulty** | **8.5 / 10** |
| **Realistically achievable?** | **Yes**, via Option D (monorepo + repo abstraction + Electron shell). Not via fork. Not via PWA. Not via runtime branching. |
| **Biggest hidden danger** | The 1,592 `school_id` references aren't dangerous; the **766 raw `getPool` call sites** are. Without a repo abstraction first, every other phase hits the same wall. |
| **Biggest architectural weakness** | **Auto-increment IDs as the canonical identity for everything sync-eligible.** This must be fixed before sync is even meaningful. |
| **Biggest strategic opportunity** | The **most recent code is the most portable**. Snapshots, DRCE, overrides, registry — all pure, deterministic, schema-versioned, JSON-portable. The team has been building offline-first patterns for the last few weeks without naming them as such. **Lean into this; it is your moat.** |
| **DRAIS as a dominant offline-first African school platform?** | **Yes, plausibly.** The market need is real. But the engineering investment is real too — this is a product line, not a feature. Underestimate at your peril. The competitive moat is *not* the offline part (others can copy that); it's the **deterministic snapshot-and-override report engine** that schools can edit without breaking their academic data. That is unusual and valuable. |
| **What MUST be fixed before implementation starts** | **(1)** Adopt the repository pattern in the cloud product first. **(2)** Stand up the monorepo. **(3)** Add UUIDs + version columns to sync-eligible tables. **(4)** Pick the SQLite library now (`better-sqlite3` + SQLCipher) and prove it against the snapshot subsystem as a beachhead. **(5)** Decide explicitly which tables are sync-bidirectional, sync-pull-only, or device-local-only — and write that decision down. **(6)** Hire or assign a sync-engine specialist; this is not a generalist task. |

### Three brutal truths

1. **The Phase 3.x DRCE work just shipped is the *easy* part of going
   offline.** Determinism, frozen snapshots, pure render layers — those
   are the patterns that *enable* offline. Most of the rest of the
   codebase doesn't follow them.
2. **There is no "weekend prototype" that proves this works.** Anyone who
   claims they can spike Electron + SQLite over a weekend is showing you
   a demo, not the product. The hard problems (sync, auth, file storage,
   conflict resolution) don't surface until month 4+.
3. **The Cloud product cannot be put on hold during the migration.** This
   means *every* refactor must be incremental, behind feature flags, with
   both old and new paths runnable side by side, until the day each new
   path is fully exercised. That is a 1.5–2× engineering tax. Plan for it.

### Where to start, concretely

If I were running this project, **week 1** would be:

1. Stand up the monorepo skeleton (no migration, just infra).
2. Move `src/lib/snapshots/`, `src/lib/drce/`, and the
   snapshot/DRCE/override types into `@drais/domain`. Cloud build still
   works.
3. Write a `SnapshotRepository` interface with one method
   (`loadSnapshot(uuid)`). One implementation against current `mysql2`.
   The print route imports the repo, not raw SQL.
4. Demo: rendering a snapshot using the repository abstraction. Look
   identical to before.

That is one week's work. After it, you have *proof* the strategy holds.
Without it, every subsequent estimate is a guess.

---

**End of assessment.**
