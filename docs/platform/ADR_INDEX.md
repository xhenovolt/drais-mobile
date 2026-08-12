# Architecture Decision Records

**This is the most important documentation in the repository.**

You can read the code to learn *what* DRAIS does. You cannot read the code to learn *why* — why a table is denormalized, why two systems that look redundant both exist, why an obvious-looking simplification would cause a production incident. That reasoning lived only in the founder's head. These records move it into the repository permanently.

## How to use these

**Before changing a subsystem, read its ADR.** Most ADRs here exist because something went wrong in production, and the design that looks strange is the fix. Several document invariants that are enforced by convention rather than by the type system — the exact category of rule a well-meaning refactor silently breaks.

**When you make a significant architectural decision, write one.** Significant means: it constrains future work, it will look wrong to someone who wasn't there, or it trades something away deliberately.

## Format

Copy [`TEMPLATE.md`](TEMPLATE.md). Number sequentially. Sections: Problem, Context, Decision, Alternatives considered, Trade-offs, Consequences, Migration notes, Related systems, Future considerations.

Write the Alternatives and Trade-offs sections honestly — an ADR that presents its decision as obviously correct with no cost is not useful. The value is in recording what was given up.

## Status meanings

- **Accepted** — in force; the code reflects this
- **Superseded** — replaced by a later ADR (linked in its header)
- **Proposed** — under discussion, not yet implemented

## Index

### Attendance & time

| ADR | Title | Status |
|---|---|---|
| [0001](0001-attendance-raw-events.md) | Attendance is stored as immutable raw events with a dual-write to the legacy table | Accepted |
| [0002](0002-device-wall-time.md) | Device wall-clock strings are the punch's identity until a single UTC conversion | Accepted |
| [0003](0003-device-time-policies.md) | Device clock drift is handled by explicit per-school time policies | Accepted |
| [0004](0004-timezone-safe-dates.md) | Date handling uses two deliberately different primitives for client and server | Accepted |

### Report cards

| ADR | Title | Status |
|---|---|---|
| [0005](0005-report-snapshot-immutability.md) | Report cards render from immutable snapshots, not live data | Accepted |
| [0006](0006-contributing-subject-invariant.md) | Aggregates and divisions derive from one canonical subject set, enforced by an integrity check | Accepted |
| [0007](0007-overall-comment-render-time-exception.md) | Overall comments are the one deliberate exception to render purity | Accepted |

### Identity, access & tenancy

| ADR | Title | Status |
|---|---|---|
| [0008](0008-two-auth-systems.md) | Control Center has its own authentication system, separate from school auth | Accepted |
| [0009](0009-parent-portal-isolation-gate.md) | The parent portal is OTP-based and gated by an explicit isolation invariant | Accepted |

### Platform & deployment

| ADR | Title | Status |
|---|---|---|
| [0010](0010-dual-database-mode.md) | TiDB Cloud and local MySQL coexist as first-class runtime modes | Accepted |
| [0011](0011-platform-api-contract-freeze.md) | The external Platform API v1 contract is frozen | Accepted |
| [0012](0012-founder-independence.md) | Founder independence is an explicit design goal, not a documentation afterthought | Accepted |
| [0013](0013-swr-as-the-client-data-layer.md) | SWR is the client data layer; `apiFetch` is the transport | Accepted |
| [0014](0014-client-rendered-app-router.md) | App Router with client components throughout, not server components | Accepted |

## Where the raw material came from

Many of these were reconstructed from forensic audits in [`../audits/`](../audits/) and incident reports now in [`../archive/`](../archive/README.md). Where an ADR is based on a specific audit or postmortem, it links to it. Those source documents remain useful for detail; the ADR is the durable summary.
