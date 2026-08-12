# ADR-0012: Founder independence is an explicit design goal, not a documentation afterthought

- **Status:** Accepted
- **Affects:** product design across all modules; `src/lib/attendance/founder-independence.ts`

## Problem

DRAIS was built by one person, and for a period it could only be *operated* by that person. Not because features were missing, but because critical knowledge existed nowhere except in his head:

- which device a school's attendance came from, and what to do when it drifted
- why a report card showed an unexpected division
- how to recover a mis-imported class
- what a given error actually meant

Every school with a problem escalated to the founder. That is a hard ceiling on how many schools the product can serve, and a single point of failure for the ones it already has. It is also an existential business risk: a product only its author can run is not a product.

The failure mode is subtle because **the software works**. Nothing is broken. The dependency is in the gap between what the system does and what an administrator can understand and act on without help.

## Context

DRAIS serves schools in Uganda with limited IT staff. The realistic operator is a bursar, headteacher, or secretary — competent and motivated, but not technical, and without a support engineer to call.

Meanwhile the underlying systems are genuinely complex: biometric devices with unreliable clocks, aggregate/division grading rules with real subtlety, multi-tenant data isolation. The complexity is inherent to the domain and cannot be removed.

So the goal cannot be "make it simple". It has to be: **surface the complexity in terms an administrator can act on.**

## Decision

**Treat founder independence as a design constraint on every feature**, evaluated during design rather than documented afterwards.

Concretely, a feature is not complete when it works. It is complete when a trained administrator can, without help:

1. **See what the system decided and why.** Not a confidence score alone — the evidence behind it. The Time Health page shows the actual first-arrival punch records backing its verdict, always, whether the day looks healthy or not. A verdict with no visible evidence is a support ticket.
2. **Understand a failure in domain terms.** "Device clock is 3 hours ahead" is actionable; a stack trace is not. Errors name the thing the operator recognizes.
3. **Recover without a developer.** Preview-then-apply with an undo path — the attendance correction flow and the Backup Center both follow this shape deliberately.
4. **Never be silently wrong.** Explicit invariants that fail loudly ([ADR-0006](0006-contributing-subject-invariant.md)) and flagged-for-review policies ([ADR-0003](0003-device-time-policies.md)) exist because a system that quietly produces wrong data creates exactly the dependency this ADR exists to remove.

The goal is tracked as a **measured, living artifact**, not an aspiration. `src/lib/attendance/founder-independence.ts` is a before/after report mapping every attendance workflow that once required the founder to what replaced it, scoring autonomy on a four-level scale (`founder → manual → assisted → automated`). Its baseline is the Phase 0 audit; its "now" column layers in live signals, so the page reflects the actual school rather than a static claim.

This documentation program is the same goal applied to engineering knowledge: [ADRs](README.md) exist so architectural intent outlives the person who formed it.

## Alternatives considered

**Hire and train a support team.** The conventional answer. It scales cost linearly with schools and does not remove the founder dependency — it adds a layer that still escalates the hard cases. Worth doing eventually, but not instead of this.

**Write comprehensive documentation and stop there.** Necessary, insufficient. Documentation explaining how to work around an opaque screen is a symptom; the screen should show its reasoning. Documentation is a complement to the design constraint, not a substitute — and unmaintained docs actively mislead ([`../archive/README.md`](../archive/README.md) is the evidence).

**Simplify the product until it needs no explanation.** Attractive, but the complexity is in the domain — devices really do have failing clocks, and grading rules really are subtle. Removing the features that handle it makes DRAIS a worse product, not a more independent one.

**Accept the dependency; stay small.** A legitimate business choice, and explicitly rejected — it caps the number of schools that can be served.

## Trade-offs

- **Features take longer.** Evidence surfaces, preview/undo flows, and explanatory errors are real work on top of the core capability, and they are the parts most tempting to cut under time pressure.
- **More UI surface** means more to maintain and more to keep translated in both languages.
- **Explanation can become noise.** Showing everything is as unhelpful as showing nothing; deciding what an administrator actually needs is a judgement call each time.
- **The autonomy scorecard is attendance-only today** — the discipline is applied more broadly than it is measured, so the metric understates and over-focuses on one module.

## Consequences

- Support load shifts from "explain what happened" to genuinely novel problems.
- Design reviews ask "could a bursar resolve this alone?" as a standard question.
- Diagnostics, audit trails, and undo paths are treated as core requirements rather than nice-to-haves — which is why they recur across otherwise unrelated ADRs here.
- Architectural reasoning is written down at decision time, because the same argument applies to engineers as to administrators.

## Related systems

- `src/lib/attendance/founder-independence.ts` — the measured scorecard
- [`../audits/FOUNDER_INDEPENDENCE_AUDIT.md`](../audits/FOUNDER_INDEPENDENCE_AUDIT.md), [`../audits/ATTENDANCE_FOUNDER_INDEPENDENCE_AUDIT.md`](../audits/ATTENDANCE_FOUNDER_INDEPENDENCE_AUDIT.md)
- [ADR-0003](0003-device-time-policies.md), [ADR-0006](0006-contributing-subject-invariant.md) — the principle applied

## Future considerations

Extend the autonomy scorecard beyond attendance to finance, academics, and devices, so the claim is measured across the product rather than asserted. Until then, treat the score as evidence for one module and the principle as applying to all of them.
