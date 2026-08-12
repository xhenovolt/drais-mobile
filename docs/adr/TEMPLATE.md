# ADR-NNNN: <short imperative title>

- **Status:** Proposed | Accepted | Superseded by [ADR-NNNN](NNNN-....md)
- **Date:** YYYY-MM-DD
- **Affects:** `src/lib/<subsystem>/`, `<table names>`, `<routes>`

## Problem

What was actually going wrong, or what needed to be possible. If this came from a production incident, say so concretely — dates, symptoms, who noticed. Avoid abstraction here; the specific failure is what makes the decision legible later.

## Context

What was true at the time that constrained the options: existing schema, deployment target, team size, data already in production, external systems (devices, payment platforms) that could not be changed.

## Decision

What was decided, stated plainly. Include the specific rule a future engineer must not break.

## Alternatives considered

Each realistic option and why it was not chosen. **An ADR with no alternatives section is usually hiding the reasoning that matters.** If the obvious simpler approach was rejected, this is where you explain why — it is the section that prevents someone re-introducing it in six months.

## Trade-offs

What this costs. Every real decision gives something up: performance, simplicity, storage, developer ergonomics, correctness in some edge case. State it honestly.

## Consequences

What follows from this — for the schema, for how features get built, for what is now hard to change.

## Migration notes

If this changed existing behaviour: what had to be migrated, what is still in a transitional state, what legacy path still exists and when it can be removed.

## Related systems

Files, tables, other ADRs, and the audits or postmortems this came from.

## Future considerations

Known limitations, deferred work, and the conditions under which this decision should be revisited.
