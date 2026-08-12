# ADR-0009: The parent portal is OTP-based and gated by an explicit isolation invariant

- **Status:** Accepted
- **Affects:** `src/lib/portal/guard.ts`, `parent_accounts`, `parent_student_links`, `/api/portal/*`

## Problem

Parents need access to their own children's results, report cards, attendance, and fee balances. Two hard constraints shape any solution:

1. **A parent must never see another family's child.** This is the highest-stakes authorization boundary in the product — a leak here is a child-safeguarding incident, not a bug report.
2. **Parents are not software users.** They are on low-end phones with intermittent data, often sharing a device, and will not reliably maintain a password for a system they use a few times a term.

## Context

Password-based accounts fail the second constraint in practice: parents forget them, password resets require a working email (many have none), and shared phones make stored credentials a liability. Phone numbers, by contrast, are already held by the school as the primary contact channel and are already used for SMS.

The relationship is also genuinely many-to-many and mutable: a parent may have children in several classes or even several schools; guardianship changes; a child transfers. So "which learners may this person see" cannot be a static property of the account.

## Decision

**Authentication is OTP over the parent's phone number** — no passwords. The number is the identity, an SMS one-time code is the proof, and SMS is a channel the school already uses and the parent already trusts.

**Authorization is a single explicit invariant**, stated at the top of `src/lib/portal/guard.ts` as "THE ISOLATION GATE":

> A parent can only ever see learners whose `student_id` is in their OWN active link set, scoped to the active school. Every data query intersects **(requested) ∩ (authorized)** — never the requested set alone.

The intersection is the operative part. A route must never take a `student_id` from the request and query it directly, even after a membership check — it must intersect the requested set with the authorized set, so an unauthorized id yields nothing rather than an error-or-data branch.

Three enforcement helpers are provided, and every portal route must use one:

- `authorizedStudentIds(parentAccountId, schoolId)` — the active link set (empty means sees nothing)
- `assertCanViewStudent(...)` — throws `PortalForbiddenError`
- `studentGateSubquery()` — embeddable in SQL for list queries

Links are scoped by school **and** by `status = 'active'`, so revoking access is a status change, and a parent with children in two schools sees each school's children only in that school's context.

## Alternatives considered

**Password accounts.** Rejected on the second constraint — forgotten passwords with no email recovery path make it unusable for the actual population.

**Magic links by email.** Most parents have no reliable email; SMS is the channel that already works.

**A shared school-wide portal code.** Trivially violates isolation.

**Row-level security in the database.** Genuinely appealing, and the right answer if the platform were PostgreSQL. TiDB's support does not make this a practical primary control here, so the gate is enforced in application code.

**Deriving access from the existing student-guardian records.** Rejected: guardian records are contact information, not an authorization grant. A number listed as an emergency contact should not automatically confer portal access — the link is a separate, explicit, revocable object.

## Trade-offs

- **The invariant is enforced by convention and code review, not by types.** This is the honest weakness. A new portal route that queries `students` directly compiles, passes tests, and leaks — which is exactly why the rule is written in capitals at the top of the file and repeated here.
- **OTP costs money and depends on SMS deliverability.** A failed SMS is a locked-out parent.
- **Phone numbers change**, and a reassigned number could reach a stale link — hence `status`-scoped links and the ability to revoke.
- **No passwords means no "something you know" factor**; possession of the phone is the whole credential.

## Consequences

- Portal access is revocable per link without touching the parent account.
- Multi-school parents are handled naturally by the school-scoped link set.
- Every portal data path has one auditable chokepoint.
- **Code review must treat "does this route go through the gate?" as a required check** for any change under `src/app/api/portal/`.

## Related systems

- `src/lib/portal/guard.ts` — the gate and its helpers
- `src/lib/portal/` — OTP, session, linking
- [ADR-0008](0008-two-auth-systems.md) — the portal is a third identity space, distinct from both school and Control Center auth
- [`../audits/PARENT_PORTAL_READINESS_AUDIT.md`](../audits/PARENT_PORTAL_READINESS_AUDIT.md)

## Future considerations

The convention-not-types weakness is the thing most worth fixing. Options: a lint rule flagging direct `students`/`class_results` queries under the portal route tree, or a repository layer that structurally cannot be constructed without an authorized id set. Either would convert a review discipline into an enforced constraint — worth doing before the portal's surface grows much further.
