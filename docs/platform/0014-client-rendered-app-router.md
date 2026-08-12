# ADR-0014: Use the App Router with client components throughout

- **Status:** Accepted
- **Date:** 2026-08-03
- **Affects:** `src/app/**`, `src/app/layout.tsx`, `src/contexts/`, `middleware.ts`

## Problem

DRAIS runs on the Next.js App Router but does not use React Server Components. Effectively every page is
`'use client'`, the root layout is a client component, and all data arrives through client-side fetches to
route handlers.

This is a deliberate position, but it was never written down. Left unstated, it invites two failure modes: a
developer adding a server component "because that's the modern way" and creating a second mental model, or a
reviewer rejecting perfectly correct client code for not being server-first.

## Context

At the time the App Router was adopted:

- **Nearly every screen is stateful and interactive.** Mark sheets with inline editing, live attendance, the
  DRCE report designer (a visual canvas editor), bulk selection across large lists, device enrolment flows.
  Almost nothing in DRAIS is a static read.
- **Every screen is session-scoped and tenant-scoped.** There is no meaningful shared cache between users, so
  the main server-rendering win — caching rendered output — does not apply.
- **Global cross-cutting state is genuinely needed:** authenticated user, current term, progress for long
  operations, theme, language/RTL. All of these are client concerns.
- **The app ships to three targets** — web (Vercel), desktop (Electron) and Android (Capacitor, embedding the
  server). A uniform client-rendered model behaves the same on all three.
- **691 route handlers already existed** as the API surface, consumed by both the web client and other callers.

## Decision

**Pages are client components. Data comes from route handlers over HTTP. The server-side surface is
`middleware.ts` plus `app/api/**/route.ts`.**

The specific rules:

1. New pages are `'use client'` unless there is a stated reason otherwise.
2. Business logic lives in `src/lib/<subsystem>/`, called from route handlers — never from a page.
3. Authentication is resolved **in the route handler**. Middleware runs on the Edge runtime, cannot reach the
   database, and therefore only checks that a session cookie is *present*.
4. Cross-cutting state lives in one of four contexts, or in the SWR cache. See ADR-0013.

## Alternatives considered

**Server components for read-heavy pages** (lists, dashboards, reports). Genuinely attractive for the learner
list and dashboards. Rejected for now because it creates two models in one codebase — two ways to fetch, two
ways to handle auth, two ways to handle errors — for a team small enough that consistency is worth more than
the render savings. It is the most likely part of this ADR to be revisited.

**Full server-first adoption.** Rejected: the DRCE editor, live attendance and inline-editable mark sheets are
irreducibly client-side, so the result would be a hybrid anyway, with the added cost of rewriting screens that
work.

**Stay on the Pages Router.** Rejected: the App Router gives nested layouts, which is exactly what the four
distinct shells (staff app, parent portal, Control Center, naked print targets) need.

**Move auth into middleware.** Rejected because it is not possible as intended — the Edge runtime cannot query
the sessions table. Attempting it would produce presence-checking dressed up as authentication, which is more
dangerous than the current explicit split.

## Trade-offs

- **Larger client bundles.** The learner list is 48.7 kB on its own; shared chunks are ~102 kB.
- **No streaming or partial hydration**, so slow screens are slow all at once.
- **SEO is irrelevant** for the app — but note the marketing site is a separate repository and does not inherit
  this decision.
- **The root layout being a client component** means every provider is client-side, and anything mounted there
  runs on every route — including routes belonging to other auth domains. This has already caused a production
  defect (see below).
- **Two auth checks** — cookie presence at the edge, real validation in the handler — must both be understood.
  A handler that trusts middleware is unauthenticated.

## Consequences

- The provider tree in `src/app/layout.tsx` executes on **every** route, including `/control`, `/portal` and
  `/parent`, which belong to other auth domains.
- Consequently, `AuthContext`'s client-side redirect must maintain an exemption list. When that list drifted
  from the middleware's, the Control Center login became unreachable without a school session. Exemptions now
  live in one shared module, `src/lib/routes/auth-scope.ts`.
- Naked print targets (`/print-snapshot`, `/print-transcript`, `/rpt`) must bypass the shell entirely, or
  global overlays are captured into printed PDFs by puppeteer.
- Every page must handle loading, error, empty and populated states itself, since there is no server-rendered
  first paint.

## Migration notes

Not a migration — this documents the existing position. If server components are adopted later, the sequence
that would minimise damage:

1. Pick one genuinely read-only, low-interaction area.
2. Move its data fetch server-side while leaving auth resolution in the same place.
3. Document the boundary explicitly in this ADR before a second area follows.

## Related systems

- `src/app/layout.tsx` — provider tree and the shell-vs-bare decision
- `middleware.ts` — Edge-runtime gating
- `src/lib/routes/auth-scope.ts` — the shared exemption list and the incident that produced it
- [ADR-0008](0008-two-auth-systems.md) — the separate auth domains that make the exemption list necessary
- [ADR-0013](0013-swr-as-the-client-data-layer.md) — the client data layer this implies

## Future considerations

- Revisit for dashboards and large lists if bundle size or time-to-interactive becomes a real complaint from
  schools rather than a theoretical concern.
- Server-side pagination for large lists is worth doing **regardless** of this decision — it is a data
  question, not a rendering one.
- If any hybrid is adopted, the boundary must be stated here first. An undocumented hybrid is the outcome this
  ADR exists to prevent.
