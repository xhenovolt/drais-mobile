# ADR-0011: The external Platform API v1 contract is frozen

- **Status:** Accepted
- **Affects:** `/api/platform/v1/*`, `src/lib/platform/`

## Problem

DRAIS exposes a Platform API consumed by external systems — most notably the Jeton payments platform. Those consumers are **deployed independently and cannot be updated in lockstep** with DRAIS.

Without an explicit contract, ordinary internal work silently breaks integrations: renaming a response field during a refactor, tightening a type, changing an error shape, or removing an endpoint that looks unused from inside the codebase. The breakage surfaces in someone else's production, not ours, and often not immediately.

## Context

DRAIS ships frequently and refactors freely — that velocity is a deliberate property of the project. The internal APIs (`/api/*`) genuinely benefit from being changeable at will.

The external surface cannot work that way. It is a small, well-defined set of endpoints (health, schools, subscriptions, usage, analytics, events, audit, webhooks) with scope-based authorization, and each is a promise to a third party.

Critically, **the boundary was not obvious from the code**: `/api/platform/v1/schools` and `/api/schools` look like sibling route files in the same tree. Nothing structurally distinguished "may change freely" from "may never change".

## Decision

**Declare an explicit, documented freeze**, recorded in [`../PLATFORM_CONTRACT_FREEZE.md`](../PLATFORM_CONTRACT_FREEZE.md) and effective from a named commit. That document is the binding contract, not a description.

Frozen: the endpoint surface (paths and methods), the response envelope, error shapes, and scope names.

The change rules are deliberately asymmetric:

- **No removals. No method changes.** Nothing in v1 disappears or changes verb.
- **New endpoints may be added** — but must **default-off** for keys that have not requested the new scope, so adding capability never widens an existing key's access.
- **Breaking changes go to `/api/platform/v2`**, a namespace reserved up front so the escape hatch exists before it is needed.

Authorization is scope-based per API key (`schools:read`, `subscriptions:write`, `webhooks:manage`, …), with IP allowlisting and rate limiting — so a key is constrained to exactly what its integration needs.

## Alternatives considered

**No formal contract; coordinate changes ad hoc.** How it worked before, and it does not scale past one consumer or one team. It also depends on remembering which routes are external, which is exactly the thing that isn't visible in the code.

**Version every endpoint independently.** More flexible, considerably more complex, and consumers then track a matrix of versions rather than one. Not justified at this surface size.

**Semantic versioning of the whole API with deprecation windows.** The heavier industry-standard answer. Rejected as premature: it requires deprecation tooling, consumer telemetry, and sunset communication processes that do not exist yet. A hard freeze plus a reserved v2 gives most of the safety for a fraction of the machinery.

**Auto-generate the contract from code (OpenAPI from route handlers).** Attractive — the contract could not drift from the implementation. Rejected for now because generated schemas describe *what the code currently does*, which is not the same as *what was promised*; a hand-written freeze document states intent, including things the code must never start doing.

## Trade-offs

- **v1 accumulates decisions we would make differently.** That is the deal — the contract's value is precisely that it does not improve.
- **The freeze is enforced by discipline and review**, not by tests. A refactor *can* break it; nothing fails automatically. This is the main weakness.
- **A v2 eventually means maintaining two surfaces** for a transition period.
- **Default-off scoping** means adding an endpoint also means coordinating scope grants with consumers before they can use it.

## Consequences

- External consumers can upgrade DRAIS without coordinating a release.
- The internal/external boundary is explicit, so an engineer can tell from the path prefix whether they are free to change something.
- Adding capability is always safe; removing or reshaping is not permitted in v1.
- Webhook subscriptions, deliveries, and retries are part of the frozen surface — the async integration path is as stable as the synchronous one.

## Related systems

- [`../PLATFORM_CONTRACT_FREEZE.md`](../PLATFORM_CONTRACT_FREEZE.md) — the binding contract
- [`../PLATFORM_API.md`](../PLATFORM_API.md) — reference: scopes, IP allowlist, rate limiting
- [`../PLATFORM_READINESS.md`](../PLATFORM_READINESS.md) — readiness and deferred follow-ups
- `src/lib/platform/` — API keys, scopes, HMAC webhooks, idempotency, rate limiting, audit
- [ADR-0008](0008-two-auth-systems.md) — platform API keys are a third auth mechanism, distinct from school and Control Center sessions

## Future considerations

The strongest available improvement is **contract tests** that assert the frozen envelope and endpoint surface, converting review discipline into CI enforcement. Worth building before a second external consumer is onboarded — the cost of a break rises sharply with each one.
