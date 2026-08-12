# ADR-0008: Control Center has its own authentication system, separate from school auth

- **Status:** Accepted
- **Affects:** `src/lib/auth.ts`, `src/lib/control/auth.ts`, `control_*` tables, `/api/control-center/*`

## Problem

Xhenvolt staff need to operate the platform across all schools — provisioning tenants, managing subscriptions and billing, investigating incidents, suspending accounts. School staff need to operate their own school and must never see another school's data.

The obvious approach is one user table with a `super_admin` role. That makes the isolation guarantee — the single most important promise in a multi-tenant school system — depend on **a role check being correct at every one of ~685 API routes**. One missing check, or one route that trusts a client-supplied `school_id`, and a school's data is exposed.

It also means a compromised school-admin account sits in the same credential space as platform-operator accounts.

## Context

This is a hosted multi-tenant platform holding children's data across independent institutions. Tenant isolation is not a nice-to-have; it is the product's core trust guarantee.

Platform operations are genuinely different in kind from school operations — different users, different session lifetime expectations, different audit requirements, different risk profile. They are not "school admin, but more".

## Decision

**Two entirely separate authentication systems** that share no tables and no session state.

| | School auth | Control Center auth |
|---|---|---|
| Entry point | `getSessionSchoolId(req)` (`src/lib/auth.ts`) | `getControlSession(req)` (`src/lib/control/auth.ts`) |
| Cookie | `drais_session` | `drais_control` |
| Tables | `sessions`, `users`, `schools` | `control_sessions`, `control_users` |
| Authorization | `requirePermission(userId, schoolId, code)` — RBAC | `canManage(role)` / `controlCan(role, action)` |
| Audit | `audit_logs` via `logAudit()` | `control_audit_logs` via `controlAudit()` |
| Extras | — | own scrypt hashing, TOTP |

The separation is stated as a boundary in `src/lib/control/auth.ts`: nothing there reads or writes `users`, `sessions`, or any school-auth table.

**The bridge is impersonation, not a shared helper.** `POST /api/control-center/impersonate` (gated on `controlCan(user.role, 'impersonate')`) calls `startImpersonation()`, which sets the *same* `drais_session` cookies a real school login would set, recording `sessions.impersonated_by_control_user`. The rest of the application — every ordinary school route — then works unchanged for that school. `getSessionSchoolId` treats a non-null `impersonated_by_control_user` as `isSuperAdmin`.

**Consequence for feature work:** when a feature needs both a school-scoped and a platform-wide entry point, write the logic as a plain function taking a resolved `schoolId`, and call it from two route families that each resolve that id their own way. **Reuse the logic, not the auth.** The Backup Center (`src/lib/backup/orchestrator.ts`) is the reference implementation.

## Alternatives considered

**One user table with a super-admin role.** Rejected: it makes cross-tenant isolation depend on correct role checks at hundreds of call sites, with silent, severe failure. The two-system split means a school session structurally *cannot* address another school — there is no code path that widens its scope.

**One auth system with a scope/tenant claim in the token.** Better than a role flag, and defensible. Rejected because it still puts platform-operator and school-user credentials in one space, and every route must still interpret the claim correctly.

**A separate Control Center application/deployment.** The strongest isolation, and seriously considered. Rejected on operational cost: it duplicates deployment, shares no UI components, and makes impersonation (which is genuinely useful for support) much harder.

## Trade-offs

- **This is the single biggest structural surprise in the codebase.** A new engineer will reasonably assume one auth system and be wrong. It costs onboarding time, which is precisely why this ADR exists.
- **Two audit trails.** A complete picture of an incident may require reading both `audit_logs` and `control_audit_logs`.
- **Some duplication** — session handling, cookie management, and expiry logic exist twice.
- **Features spanning both need deliberate factoring** into auth-free core logic, which is more work than a single guarded route.

## Consequences

- A school session cannot be escalated to cross-tenant access; there is no role to grant.
- Platform-operator actions are separately auditable.
- Impersonation gives support the ability to see exactly what a school sees, with an explicit record of who did it.
- Any new feature needing both surfaces follows the orchestrator pattern.

## Related systems

- `src/lib/auth.ts`, `src/lib/control/auth.ts`, `src/lib/control/permissions.ts`
- `src/lib/backup/orchestrator.ts` — reference pattern for dual-surface features
- [`../RBAC_ARCHITECTURE.md`](../RBAC_ARCHITECTURE.md)
- [`../audits/CONTROL_CENTER_ARCHITECTURE_AUDIT.md`](../audits/CONTROL_CENTER_ARCHITECTURE_AUDIT.md)

## Future considerations

Impersonation is the one place the boundary is intentionally crossed, so it deserves the most scrutiny: session lifetime, and whether impersonated sessions should be more visibly marked in the UI for the school being impersonated.
