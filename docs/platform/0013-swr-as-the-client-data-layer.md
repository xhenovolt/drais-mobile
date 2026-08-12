# ADR-0013: Standardise on SWR as the client data layer

- **Status:** Accepted
- **Date:** 2026-08-03
- **Affects:** `src/app/**/page.tsx`, `src/hooks/`, `src/lib/apiClient.ts`, `src/app/layout.tsx`

## Problem

Three client data-fetching approaches coexist in DRAIS, and a developer writing a new screen has no stated
default. Measured at the time of writing:

| Approach | Files |
|---|---|
| `useSWR` | ~165 |
| Raw `fetch` in a component | ~122 pages |
| `apiFetch` (`@/lib/apiClient`) | 34 |
| TanStack Query (`useQuery`) | **4** |

`QueryClientProvider` is mounted globally in the root layout for those four files. Two independent caches can
hold the same server data with no invalidation relationship between them, and new code was being written
against whichever pattern the author happened to have seen last.

## Context

- Nearly every DRAIS screen is the same shape: fetch a school-scoped list, display it, mutate it, revalidate.
- Route URLs already encode the tenant scope, so a URL is a naturally correct cache key.
- The app is client-rendered throughout (see ADR-0014); there is no server-component data path to fall back on.
- `apiFetch` already exists and is documented as mandatory: *"ALL client-side API calls MUST go through
  apiFetch. Direct fetch() is forbidden."* Its guarantee is a success toast on every mutation, an error toast
  on every failure, and a throw on failure — the client half of the zero-silent-failures standard.

## Decision

**SWR is the data layer for anything read and re-read. `apiFetch` is the transport for every client-side call.**

Concretely:

1. **New reads use `useSWR`.** The global `SWRConfig` supplies the fetcher and sets `revalidateOnFocus: false`
   and `shouldRetryOnError: false`. Callers do not re-specify these.
2. **New mutations use `apiFetch`, then `mutate(key)`.** Never raw `fetch`.
3. **Do not add `useQuery`.** TanStack Query is retained only for the four existing files.
4. **After any write, invalidate.** A missing `mutate(key)` is the most common cause of "stale data" bug
   reports that are not bugs.

`revalidateOnFocus` is disabled deliberately: a bursar tabbing between windows should not re-query a large
ledger on every focus event.

## Alternatives considered

**Standardise on TanStack Query instead.** It is the more capable library — better mutation ergonomics,
devtools, richer invalidation. Rejected because adoption is 4 files against ~165: standardising on it means
migrating 165 files to gain features this application does not currently need. The migration cost is real and
the benefit is speculative.

**Keep both, with a documented boundary** (e.g. Query for mutations, SWR for reads). Rejected because any
boundary rule is forgotten under deadline, and the failure mode — two caches disagreeing about the same data —
is silent and hard to diagnose.

**Remove `QueryClientProvider` and migrate the four files now.** Attractive, and the right eventual end state.
Deferred rather than rejected: it is a small isolated change, but bundling it into this decision would make an
otherwise documentation-only change into a code change touching the root layout.

**Adopt server components and `fetch` with Next.js caching.** Rejected for the reasons in ADR-0014 — nearly
every screen is stateful and session-scoped.

## Trade-offs

- **SWR is less capable for complex mutation flows.** Optimistic updates and dependent mutations are more
  manual than in TanStack Query. Accepted: DRAIS mutation flows are mostly simple.
- **`QueryClientProvider` stays mounted** for four files, costing a small amount of bundle and one more
  provider in the tree.
- **`apiFetch` adoption is 34 files against ~122 pages using raw `fetch`.** The policy is stated but the
  codebase has not caught up; this ADR does not fix that, it only stops the gap widening.
- **Cache-key discipline is on the developer.** Two components fetching the same data with different key
  strings get two cache entries.

## Consequences

- A developer writing a new screen has one answer, and the playbooks state it.
- Converting a raw-`fetch` call site to `apiFetch` is a safe incidental improvement when touching an old file,
  and gains error surfacing for free.
- Any future proposal to introduce a third data layer needs to supersede this ADR.

## Migration notes

- **No migration required.** Existing SWR and raw-`fetch` code continues to work.
- The four `useQuery` files are left alone. When one is next substantially modified, converting it to SWR and
  then removing `QueryClientProvider` is the natural cleanup.
- Raw `fetch` → `apiFetch` conversion is opportunistic, not a scheduled task.

## Related systems

- `src/lib/apiClient.ts` — the mandated wrapper and its guarantees
- `src/app/layout.tsx` — the provider tree
- `docs/guides/API_ERROR_HANDLING_GUIDE.md` — the server half of zero silent failures
- [ADR-0014](0014-client-rendered-app-router.md) — why there is no server-component data path

## Future considerations

- Revisit if mutation flows become genuinely complex (offline queues, optimistic multi-step writes), where
  TanStack Query's model would start to pay for itself.
- Revisit if server components are adopted for any read-heavy area.
- Consider a lint rule forbidding raw `fetch` in `src/app` and `src/components`, which would enforce the
  `apiFetch` rule mechanically rather than by convention.
