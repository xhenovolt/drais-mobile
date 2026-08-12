# DRAIS Mobile documentation

DRAIS Mobile is a client of the DRAIS platform. This documentation assumes you may never have seen the LongTerm repository — the decisions that constrain this codebase are copied into [`platform/`](platform/README.md) so the project is understandable on its own.

## Start here

| If you are… | Read |
|---|---|
| New to the codebase | [ARCHITECTURE](ARCHITECTURE.md), then the five mobile ADRs below |
| Adding a feature module | [ROADMAP](ROADMAP.md) → "How to add a module", then [CODING_STANDARDS](CODING_STANDARDS.md) |
| Setting up a build | [ENVIRONMENTS](ENVIRONMENTS.md) |
| Releasing | [VERSIONING](VERSIONING.md), [CHANGELOG](../CHANGELOG.md) |
| Wondering why mobile differs from web | [PARITY](PARITY.md) |
| Asked "does it work offline?" | [OFFLINE_STRATEGY](OFFLINE_STRATEGY.md) |
| Working on the backend and affected by mobile | [PARITY §3](PARITY.md) — observed platform debt |

## Mobile decision records

Decisions made *for this client*. Written in the same form as LongTerm's ADRs, numbered `M` to keep the two sequences distinct.

| ADR | Decision |
|---|---|
| [M0001](adr/M0001-riverpod-as-state-and-di.md) | Riverpod is both the state manager and the dependency injector |
| [M0002](adr/M0002-cookie-session-parity.md) | Mobile authenticates with the platform's session cookie, not a token |
| [M0003](adr/M0003-go-router-navigation.md) | Navigation is declarative, and every auth gate is a router redirect |
| [M0004](adr/M0004-no-business-logic-in-the-client.md) | The client contains no business logic and no database access |
| [M0005](adr/M0005-hand-written-serialization.md) | JSON serialisation is hand-written, not generated |

Write a new one — copy [`adr/TEMPLATE.md`](adr/TEMPLATE.md) — when a decision **constrains future work, will look wrong to someone who wasn't there, or trades something away deliberately**. That is LongTerm's test, and it applies unchanged.

## Mobile guides

| Document | Covers |
|---|---|
| [ARCHITECTURE](ARCHITECTURE.md) | Layers, directory map, request lifecycle, the five non-obvious things |
| [PARITY](PARITY.md) | What is inherited, what differs deliberately, and platform technical debt |
| [ENVIRONMENTS](ENVIRONMENTS.md) | dart-defines, the `.env` mapping, what must never ship in a binary |
| [VERSIONING](VERSIONING.md) | Why mobile starts at 1.0.0, and `verifiedAgainstLongTerm` |
| [OFFLINE_STRATEGY](OFFLINE_STRATEGY.md) | What works offline, why it stops there, and the path forward |
| [CODING_STANDARDS](CODING_STANDARDS.md) | Non-negotiables, layering, naming, comments, testing |
| [ROADMAP](ROADMAP.md) | Module order, how to add one, and what the platform owes mobile |

## Inherited platform documentation

[`platform/`](platform/README.md) holds copies of the LongTerm documents that bind this codebase — ADRs 0008–0014, the RBAC architecture, the error-handling standard, the table dictionary, and the platform API contract.

**They are read-only here.** Edit the original in LongTerm and re-copy. A divergent copy answers the reader's question wrongly, which is worse than having no copy at all.
