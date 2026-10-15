# M0006: Direct mode is the primary path, and it ports LongTerm's logic

- **Status:** Accepted
- **Date:** 2026-09-29
- **Affects:** every `features/*/data/direct/` directory; amends [M0004](M0004-no-business-logic-in-the-client.md) for direct mode

## Problem

The goal of DRAIS Mobile is to run DRAIS on a phone, fast. [M0004](M0004-no-business-logic-in-the-client.md) assumed a server between the phone and the database, so the client could render what the server computed. Direct mode ([DEPLOYMENT_MODES](../DEPLOYMENT_MODES.md), Mode C) removes that server: the app opens the TiDB connection itself. With no server, the logic that server would have run must run on the device, or it does not run at all.

## Decision

**In direct mode, the app is the DRAIS backend.** Each module reproduces LongTerm's route handlers and libraries in Dart: the same SQL, filters, fallbacks, thresholds and quirks.

1. **Port, don't invent.** Every piece of logic in `data/direct/` names the LongTerm file it came from. Pure libraries are ported line for line into `data/direct/longterm/`, and their tests are transcribed from LongTerm's `__tests__/`.
2. **Logic stays in `data/direct/`.** `domain/` still holds only entities and interfaces, and `application/` and `presentation/` never see SQL. Swapping in an API-backed repository later changes nothing above `data/`.
3. **Tenant scope comes from the session.** Every query takes `school_id` from the validated session row, never from the UI.
4. **Side effects that LongTerm hides inside reads are not ported silently.** Each one is either reproduced or listed in [PARITY](../PARITY.md) §4.
5. **One statement per round trip counts.** On a phone link each query is a TLS round trip to TiDB Cloud, so ports may merge or parallelise statements **only when the result is provably identical** (for example, computing a total and the tab badges in one pass). Behaviour never changes for speed.

M0004's rules 1 and 2 (no database access, no business rules) now apply to **API mode only**. Its rule on tenant scope applies to both modes.

## Consequences

- A rule change in LongTerm must be re-ported here. `verifiedAgainstLongTerm` and PARITY §4 are how drift is tracked, and the transcribed tests catch it in pure logic.
- Anyone holding a direct-mode build holds the database credential for every school. DEPLOYMENT_MODES' warning stands, and the recommendation is unchanged: direct-mode builds belong on devices the school controls.
- Direct mode is not automatically faster than a server. A server next to the database pays one network hop per screen; a phone pays one per SQL statement. Ports must keep statement counts low for the speed goal to hold.
