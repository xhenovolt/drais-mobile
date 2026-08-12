# DRAIS RBAC Architecture

> Enterprise-grade dynamic RBAC with super-admin absolute control,
> declarative permission catalog, automatic DB sync, and granular
> module.resource.action codes.

---

## 1. Current state (the problem)

| Metric | Value | Implication |
|---|---|---|
| Permissions in DB | 36 | Looks rich |
| Permissions actually enforced in code | **13** | 23 declared, never checked |
| Critical routes with NO `requirePermission` gate | ~80% of `src/app/api` | Authorization is mostly absent |
| Permission naming consistency | Mixed (`role.read` vs `roles.read`, `user.create` vs `staff.create`) | Drift over time |
| Super-admin lockout incidents (prod) | 1 confirmed (ALBAYAN, fix shipped today) | The flag-only check is fragile |
| Catalog of available permissions | None — only what's in the DB | Founder must hand-maintain rows |
| Permission tree / grouping UI | None — flat checkbox list | Cannot scale past ~50 codes |

### Architecture weaknesses

1. **No declarative source of truth.** Permissions are DB rows. If a developer adds a new route and forgets to insert a permission, the route is silently world-open or silently locked.
2. **No granularity by curriculum or department.** The brief's example — a DOS Secular should not access theology — is **impossible to express** today. There's no `academics.theology.*` vs `academics.secular.*` split.
3. **Wildcards not supported.** `userCan` checks exact string match. Granting "all academics" requires 30+ rows in `role_permissions`.
4. **Super-admin recognition fragile.** Just fixed: flag-only check failed when role had slug='super_admin' but `is_super_admin=0`. New code recognises super-admin by flag OR slug OR canonical name.
5. **Authorization scattered.** Some routes use `requirePermission` from `src/lib/rbac.ts`. Others use `requirePermission` from `src/lib/auth/apiAuth.ts`. Module gating uses `checkModule` from `src/lib/auth/requireModule.ts`. Trash uses `withErrorHandling`. No single authorize() entrypoint.
6. **No sync mechanism.** Adding a new permission means hand-writing an `INSERT` SQL migration. There's no `POST /api/admin/permissions/sync` to bring DB in line with code.

---

## 2. Target architecture

### 2.1 Declarative permission catalog

`src/lib/rbac/catalog.ts` is the **single source of truth** for what permissions exist. Every permission is a typed const:

```ts
export const PERMISSIONS = {
  // ─── Academics ─────────────────────────────────────────────────
  'academics.secular.view':            { module: 'academics', resource: 'secular', action: 'view',   description: 'View secular curriculum data' },
  'academics.secular.manage':          { module: 'academics', resource: 'secular', action: 'manage', description: 'Create / update secular records' },
  'academics.theology.view':           { module: 'academics', resource: 'theology', action: 'view',  description: 'View theology / Quran curriculum data' },
  'academics.theology.manage':         { module: 'academics', resource: 'theology', action: 'manage', description: 'Create / update theology records' },
  // … ~150 entries total
} as const;

export type PermissionCode = keyof typeof PERMISSIONS;
```

Benefits:
- **Type-safe.** `requirePermission(s, 'academics.theology.view')` is checked at compile time.
- **Documented.** Each permission carries `description` shown in the UI.
- **Grouped.** `module` + `resource` + `action` drive the tree UI.
- **Auditable.** Removing a permission from the catalog flags it as orphaned in the next sync — never silently destroyed.

### 2.2 Sync engine

`POST /api/admin/permissions/sync` (super-admin only) reconciles DB with catalog:

| Catalog | DB | Action |
|---|---|---|
| Present | Absent | `INSERT` with `is_active = 1` |
| Present | Present | `UPDATE` description/module/resource/action if changed; ensure `is_active = 1` |
| Absent | Present (active) | Mark `is_active = 0` (orphan — preserved for audit, won't show in UI) |
| Absent | Present (inactive) | No-op |

**`role_permissions` is never touched.** Reassignments preserve user intent.

The sync runs:
- Automatically on application startup (idempotent)
- Manually via the admin UI button
- Via CLI for CI checks

### 2.3 Super-admin absolute access

Already shipped today (commit `b0b7ec5`): both `session.isSuperAdmin` and `userCan()` recognise super-admin by:

1. `role.is_super_admin = TRUE`, OR
2. `LOWER(role.slug) = 'super_admin'`, OR
3. `LOWER(TRIM(role.name)) IN ('super admin', 'superadmin')`

Slug is the canonical contract. Flag drift cannot lock a super-admin out again.

### 2.4 Wildcard / hierarchy support

`userCan(user, 'academics.theology.view')` returns true if the user holds:

- The exact code `academics.theology.view`, OR
- A parent wildcard:`academics.theology.*` or `academics.*` or `*`

Implementation: at check time, decompose the requested code into its prefix chain (`academics.theology.view` → `[academics.theology.view, academics.theology.*, academics.*, *]`) and `IN`-query.

Reduces grant size from 30 rows to 1 row for typical "all academics" assignments.

### 2.5 Centralised authorize helper

One function. One file. Everyone uses it.

```ts
// src/lib/rbac/authorize.ts
export async function authorize(
  session: SessionInfo,
  code: PermissionCode | string,
  opts?: { schoolScope?: number }
): Promise<{ allowed: boolean; reason?: string }>;
```

- Super-admin bypass built in (mirrors `userCan` defense in depth)
- Wildcard expansion built in
- Returns structured result (never throws — callers decide)
- Existing `requirePermission` thin-wraps it for backward compat

### 2.6 Permission tree UI

`/admin/roles/[id]` gets a new tree component:

```
☐ Academics
  ☑ Secular
    ☑ View
    ☑ Manage
    ☐ Reports
  ☐ Theology
    ☐ View
    ☐ Manage
    ☐ Reports
☐ Finance
  ☐ Fees
    ☐ View
    ☐ Manage
  …
```

Features:
- Search by code or description
- Parent checkbox auto-grants the wildcard
- "Effective permissions" preview shows what the user actually gets after wildcards expand

---

## 3. Permission catalog scope (this phase)

~150 codes spanning every operational module:

| Area | Codes | Examples |
|---|---|---|
| Academics | ~30 | `academics.secular.view`, `academics.theology.manage`, `academics.results.approve`, `academics.snapshots.generate`, `academics.reports.publish` |
| Learners | ~12 | `learners.view`, `learners.create`, `learners.archive`, `learners.promote`, `learners.bulk_import`, `learners.merge` |
| Staff & HR | ~20 | `staff.view`, `staff.account.manage`, `staff.employment.manage`, `staff.qualifications.manage`, `staff.positions.manage` |
| Roles & Permissions | ~6 | `roles.view`, `roles.create`, `roles.assign`, `permissions.view`, `permissions.sync` |
| Departments | ~4 | `departments.view`, `departments.create`, `departments.manage`, `departments.archive` |
| Attendance | ~10 | `attendance.view`, `attendance.mark`, `attendance.devices.manage`, `attendance.export` |
| Finance | ~15 | `finance.view`, `finance.fees.manage`, `finance.payments.record`, `finance.expenditures.approve`, `finance.waivers.manage`, `finance.ledger.view` |
| Payroll | ~6 | `payroll.view`, `payroll.salaries.manage`, `payroll.payments.process` |
| Tahfiz | ~10 | `tahfiz.view`, `tahfiz.records.manage`, `tahfiz.groups.manage`, `tahfiz.reports.view` |
| DRCE | ~6 | `drce.templates.view`, `drce.templates.edit`, `drce.templates.publish` |
| Trash | ~4 | `trash.view`, `trash.archive`, `trash.restore`, `trash.purge` |
| System admin | ~15 | `audit.view`, `sessions.terminate`, `school.modules.manage`, `school.settings.manage` |
| Inventory | ~4 | `inventory.view`, `inventory.manage` |
| Examinations | ~6 | `examinations.view`, `examinations.manage`, `examinations.deadlines.manage` |
| Analytics & Intelligence | ~4 | `analytics.view`, `intelligence.view` |

---

## 4. Schema evolution

`permissions` table gets three optional columns (already has `category`, `name`, `description`, `is_active`):

```sql
ALTER TABLE permissions
  ADD COLUMN module   VARCHAR(40)  NULL AFTER code,
  ADD COLUMN resource VARCHAR(40)  NULL AFTER module,
  ADD COLUMN action   VARCHAR(40)  NULL AFTER resource;
```

These power the tree UI (group by module → resource → action). Indexed lookup is `(module, resource, action)`.

No FK changes. `role_permissions` is unchanged.

---

## 5. Migration strategy (per-phase)

| Phase | Scope | Risk | This session? |
|---|---|---|---|
| **R1** | Catalog file + sync engine + `module`/`resource`/`action` columns + migration that runs sync once | LOW (additive) | ✅ |
| **R2** | Centralised `authorize()` + `requirePermission` shim + wildcard support | LOW | ✅ |
| **R3** | Permission tree UI for `/admin/roles/[id]` | MEDIUM (UI work) | partial |
| **R4** | Wire `requirePermission` into the ~80% of routes currently ungated. ~30 routes per follow-up commit. | HIGH (could lock out users; needs careful permission assignment per role) | Roadmap |
| **R5** | Codebase scanning lint rule: any `requirePermission('foo.bar')` where `'foo.bar' ∉ catalog` fails CI | MEDIUM | ✅ Shipped — `npm run lint:permissions` |
| **R6** | Department-scoped policies, ABAC, ownership-based access | HIGH (architectural) | Roadmap |

---

## 6. Edge cases & invariants

| Concern | Handling |
|---|---|
| Catalog removes a permission still assigned to a role | Marked `is_active=0` — the assignment row stays, the UI hides it, `userCan` returns false. Reversible. |
| Two devs add the same code in parallel | Catalog has a TypeScript `as const` — duplicates fail compile |
| Permission rename | Treat as orphan + new code. Manual reassignment via the UI. (Future: alias table) |
| Super-admin loses every role | The session resolver returns `isSuperAdmin: false`, but the slug/name check above also fails — they're locked out. **Resolution: keep one user with slug='super_admin' assignment always (DB constraint future)** |
| Wildcard granted but specific permission needed for a feature | Wildcard wins. By design — that's the value of wildcards. |
| Sync runs while permissions are being checked | Each `userCan` is a read; sync writes are atomic per-row UPSERT. No window where a permission becomes invisible mid-request. |
| Tenant isolation | Permissions are global codes; role_permissions are global; user_roles is per-school. School scope flows from the session, not the permission catalog. |

---

## 7. Testing strategy

- **Unit:** `authorize()` against a mock session — super-admin, exact match, wildcard, deny path.
- **Catalog integrity:** every `PermissionCode` referenced in code must exist in the catalog. CI check.
- **Sync idempotency:** run sync twice, assert second run is a no-op (zero INSERT/UPDATE).
- **Role lockout safety:** simulate revoking the last super-admin role and verify the system reports the danger before allowing it.

---

## 8. Production rollout

1. **Migration (additive)** — adds 3 nullable columns. Safe.
2. **First sync run** — INSERTs ~120 missing permissions. Existing 36 get matched & updated.
3. **Permission assignment** — super-admin assigns the new granular perms to existing roles via the UI. Until they do, those new perms are unused.
4. **Wire ungated routes** (Phase R4) — one PR per module. Each adds `requirePermission` calls + sensible defaults for the existing built-in roles.
5. **Cutover** — emergency_html and trash routes already use authorize patterns; new routes inherit the pattern.

Rollback: revert the migration (drop 3 columns), revert code. Existing `role_permissions` assignments unchanged.

---

## 9. Post-rollout issues observed + fixes

### Regression — orphaned legacy codes (caught + fixed)

The first sync run renamed ~30 short-form codes (`staff.read`, `roles.read`,
`trash.read`, `audit.read`, etc.) by orphaning them in favour of the new
granular triplet form (`staff.profile.view`, `roles.role.view`, etc.). 220+
existing `role_permissions` rows referenced those orphaned codes, so every
non-super-admin role that depended on them was silently denied (super-admin
bypass masked the impact during initial testing).

Fix shipped in `src/lib/rbac/catalog.ts`: a `LEGACY_ENTRIES` block re-declares
every short-form code as a first-class catalog entry under the `_legacy`
resource bucket. Re-running sync reactivated all 29 affected rows in one
pass. Granular codes remain primary; legacy codes remain valid for
backwards compatibility.

Going forward: routes that move to the granular catalog stay using granular
codes; routes that still reference legacy codes continue to work. Migration
is per-route, no big bang.

### Standing R4 scope — what's still ungated

Inventoried May 2026, after R5 lint went green:

| Module                | Routes | Ungated (only session-checked) |
|---|---|---|
| `/api/finance/*`      |   32   |   **32**  (100%) |
| `/api/students/*`     |   53   |   **52**  (98%) |
| `/api/academics/*`    |    4   |   **4**   |
| `/api/terms/*`        |    3   |   **3**   |
| `/api/classes/*`      |    1   |   **1**   |
| `/api/subjects/*`     |    1   |   **1**   |
| `/api/admin/*`        |  many  |   **0**  ✅ |
| `/api/tahfiz/*`       |   23   |   0  ✅ (module-gated in Phase F) |
| `/api/intelligence/*` |    9   |   0  ✅ (module-gated in Phase F) |

This is the true R4 backlog: ~93+ routes that need explicit permission
gates. **Cannot be done in a single commit safely** — each module needs:

1. Mapping each route to its appropriate granular permission code
2. Verifying the per-school role grants. Schools where `teacher` already
   has `finance.view` will continue working; schools where it doesn't
   will lose access the moment the gate lands. Need an audit / migration
   per gate.
3. Staged rollout: gate WRITE routes first (POST/PUT/DELETE/PATCH) since
   they carry the most damage potential, then READ routes.

Recommended sequence:
- Finance writes (~12 routes) → require `finance.fees.manage`, `finance.payments.record`, etc.
- Students writes (~20 routes) → require `learners.profile.update`, `learners.profile.create`, etc.
- Academics writes (~4 routes) → require `academics.results.enter`, `academics.classes.manage`, etc.
- Then reads in the same modules
- Finally, the trickle: every `/api/notifications`, `/api/biometric`, etc.

Each commit gates one module's writes, one module's reads. Per-school role-grant
fix script runs alongside. The lint (`npm run lint:permissions`) catches
any typo introduced during the rewrite.
