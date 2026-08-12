# M0004: The mobile client contains no business logic and no database access

- **Status:** Accepted
- **Date:** 2026-08-05
- **Affects:** every layer; this is the rule the architecture exists to protect

## Problem

The single largest long-term risk to this project is not a bug. It is **drift**: the mobile app slowly acquiring its own opinion about grading, fee balances, attendance rules, term boundaries or access control, until the two codebases disagree about what is true and neither can be corrected without breaking the other.

Drift is not introduced deliberately. It arrives one reasonable shortcut at a time — computing a total on the device to avoid a round trip, checking an expiry date locally to skip a call, caching a rule that "never changes".

## Context

- DRAIS holds children's academic records across independent institutions. Two systems disagreeing about a learner's grade or a school's outstanding balance is a trust failure, not a display bug.
- The business rules are genuinely intricate: bilingual report generation, division and aggregate calculation, multiple grading schemes per school, term resolution, fee rules, snapshot immutability ([ADR-0005](../platform/ADR_INDEX.md)). Several have their own ADRs recording why they work the way they do.
- The server already owns all of it, and is the only place with the complete data to evaluate it.
- Tenant isolation is enforced by deriving `school_id` from the session and **ignoring any client-supplied value** ([ADR-0008](../platform/0008-two-auth-systems.md)).

## Decision

**The mobile app renders what the server computed. It computes nothing of consequence itself.**

Four rules, in force everywhere:

1. **No database access, ever.** The app never opens a MySQL or TiDB connection. `TIDB_*`, `LOCAL_MYSQL_*` and `DB_*` are not read by `AppConfig` and must never be added — anything in an APK is readable by anyone holding the APK. Every byte goes through the HTTP API.
2. **No business rules.** No grade calculation, no fee arithmetic, no attendance classification, no term resolution, no promotion logic. If a number is shown, the server produced it.
3. **No authorization decisions.** `PermissionSet` mirrors the server's wildcard semantics *to decide what to draw*. It is never a security boundary — the server re-checks every request with `requirePermission()`.
4. **No client-derived scope.** `school_id` is never sent as a parameter. `CookieStore.schoolIdHint` exists for diagnostics only and is documented as such.

### What the client *is* allowed to compute

The line is not "no logic at all", so it is worth stating precisely. The client may:

- format and localise values the server produced;
- validate input shape before sending it (an empty field, a malformed email), **as a courtesy that the server independently repeats**;
- decide what to render, including hiding controls the user lacks permission for;
- manage its own device concerns — cache freshness, retry backoff, navigation.

The test: *if the server and the client disagreed about this, would a user be misinformed about their school's data?* If yes, it belongs on the server.

## Alternatives considered

**Duplicate selected rules for offline capability.** The tempting one, and the reason this ADR exists. Marking attendance offline is a real need in schools with intermittent connectivity. Rejected as a *foundation* decision because it requires the device to know the attendance rules, the term calendar and the school-days configuration — and a device that knows those will eventually be wrong about them. [ADR-0010](../platform/0010-dual-database-mode.md) records that the platform reached the same conclusion about sync: it is an unsolved design problem, not an implementation gap. The path forward is in [OFFLINE_STRATEGY](../OFFLINE_STRATEGY.md), and it is an outbox of *intents* replayed to the server — not rules on the device.

**A shared rules package compiled to both TypeScript and Dart.** Elegant in theory. Rejected: it means a third artefact to version, release and keep in step with two consumers, and the rules depend on data the device does not have.

**Cache computed results aggressively to reduce round trips.** Partly adopted — `CacheStore` caches *responses*, which are the server's answers. It never caches inputs to re-derive an answer locally.

## Trade-offs

- **More round trips.** The app asks the server things a smarter client would work out. On a slow connection this is felt. Accepted: correctness over latency, and the cache absorbs most of the repeat cost.
- **Offline is read-only in 1.0.0.** The honest limitation, stated plainly in [OFFLINE_STRATEGY](../OFFLINE_STRATEGY.md) rather than half-solved.
- **The app is coupled to the internal API**, which — unlike the frozen Platform API ([ADR-0011](../platform/0011-platform-api-contract-freeze.md)) — may change freely. This is a real cost and is managed in [PARITY](../PARITY.md) and by the `verifiedAgainstLongTerm` constant, not avoided.

## Consequences

- A rule change ships once, on the server, and both surfaces get it — including devices that will not be updated for months.
- There is no scenario where the mobile app shows a different grade or balance than the web app.
- Mobile releases are decoupled from business-rule releases.
- Reviewing a mobile PR for correctness means checking that it *asked* rather than *decided*.

## How this is enforced

By review, and by the structure making the alternative awkward: repositories return server data, `domain/` entities have no computation beyond formatting, and the transport layer is the only route to information. There is no lint that catches "you calculated a fee balance". The reviewer's question is: **where did this number come from?**
