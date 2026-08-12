# DRAIS Platform API — v1 Contract Freeze

**Status:** FROZEN. Effective from commit `a16dcb6`.
**Successor namespace:** `/api/platform/v2` (reserved; not yet built).

This document is the binding contract for every external consumer of the
DRAIS Platform API. After this freeze, the rules below govern what may and
may not change in v1.

---

## 1. What is frozen

### 1.1 Endpoint surface (paths + methods)

| Method | Path | Scope |
|---|---|---|
| GET    | `/api/platform/v1/health` | `health:read` |
| GET    | `/api/platform/v1/ops` | `audit:read` |
| GET    | `/api/platform/v1/schools` | `schools:read` |
| GET    | `/api/platform/v1/schools/{external_id}` | `schools:read` |
| PATCH  | `/api/platform/v1/schools/{external_id}` | `schools:write` |
| POST   | `/api/platform/v1/schools/{external_id}/suspend` | `schools:write` |
| POST   | `/api/platform/v1/schools/{external_id}/reactivate` | `schools:write` |
| GET    | `/api/platform/v1/subscriptions/{external_id}` | `subscriptions:read` |
| PUT    | `/api/platform/v1/subscriptions/{external_id}` | `subscriptions:write` |
| GET    | `/api/platform/v1/usage` | `usage:read` |
| GET    | `/api/platform/v1/analytics` | `analytics:read` |
| GET    | `/api/platform/v1/events` | `events:read` |
| GET    | `/api/platform/v1/audit` | `audit:read` |
| GET    | `/api/platform/v1/webhooks` | `webhooks:manage` |
| POST   | `/api/platform/v1/webhooks` | `webhooks:manage` |
| GET    | `/api/platform/v1/webhooks/{id}` | `webhooks:manage` |
| PATCH  | `/api/platform/v1/webhooks/{id}` | `webhooks:manage` |
| DELETE | `/api/platform/v1/webhooks/{id}` | `webhooks:manage` |
| GET    | `/api/platform/v1/webhooks/{id}/deliveries` | `webhooks:manage` |
| POST   | `/api/platform/v1/webhooks/{id}/deliveries/{deliveryId}/retry` | `webhooks:manage` |

**Frozen.** No removals. No method changes. New endpoints may be added; they
must default-off for keys that don't request the new scope.

### 1.2 Response envelope

Success:
```json
{ "success": true, "data": <T> }
```

Error:
```json
{ "success": false, "error": { "code": "<CODE>", "message": "<text>", "details"?: <any> } }
```

Always-present response headers:

| Header | Meaning |
|---|---|
| `X-Request-Id` | UUID for cross-system correlation; consumers should log this |
| `X-Api-Version` | `v1` |
| `X-RateLimit-Limit` / `Remaining` / `Reset` | Standard rate-limit headers |
| `Retry-After` | Present on 429 |
| `X-Idempotent-Replay: true` | Present when a cached idempotent response is replayed |
| `Cache-Control: no-store` | All platform responses are uncacheable by intermediaries |

### 1.3 Error codes (frozen enum)

```
UNAUTHORIZED
KEY_REVOKED
KEY_EXPIRED
IP_NOT_ALLOWED
INSUFFICIENT_SCOPE
NOT_FOUND
BAD_REQUEST
CONFLICT
PAYLOAD_TOO_LARGE
RATE_LIMITED
SERVER_ERROR
SERVER_MISCONFIGURATION
```

**Frozen.** New codes may be added in v1 (consumers MUST tolerate unknown
codes by treating them as `SERVER_ERROR`-class). No code will be renamed or
repurposed.

### 1.4 Pagination contract

Every list endpoint accepts:
- `limit` (integer, capped per endpoint; default 50)
- `cursor` (opaque integer; obtained from a prior `next_cursor`)

Every list endpoint returns:
```json
{ "items": [...], "next_cursor": <number|null>, "limit": <number> }
```

`next_cursor: null` means end of stream. Consumers MUST treat the cursor as
opaque (don't parse it). Cursors are stable within v1.

### 1.5 Authentication

Token format: `pk_(live|test)_<keyId>.<secret>`

Two equivalent transports:
```
Authorization: Bearer pk_live_<keyId>.<secret>
X-Api-Key:           pk_live_<keyId>.<secret>
```

`Authorization: Bearer` is the canonical form. `X-Api-Key` is accepted for
clients that cannot set `Authorization`.

Tokens are issued via `POST /api/admin/platform-keys` (cookie-authenticated,
super-admin only). The secret half is shown ONCE and stored as bcrypt.

### 1.6 Scopes (frozen)

```
health:read           schools:read         schools:write
subscriptions:read    subscriptions:write  usage:read
analytics:read        events:read          webhooks:manage
audit:read
```

`*` is reserved for the operator-side `internal_ops` key. Never grant `*` to
external consumers.

### 1.7 Event names (frozen)

```
school.created              school.updated         school.suspended
school.reactivated          school.deleted
subscription.changed        subscription.expiring  subscription.expired
payment.received            sms.balance.low
learner.limit.exceeded      tenant.health.degraded
```

**Frozen.** New event names may be added. Subscribers using `event_types: ["*"]`
will receive new events automatically; subscribers with explicit allowlists
will not.

Event payloads are versioned implicitly by the event name itself. To change a
payload's structure incompatibly, emit a new event (e.g. `school.created.v2`)
and continue emitting the old one through a deprecation window.

### 1.8 Webhook delivery contract

**Outbound request:**
```
POST <subscription.url>
Content-Type:        application/json
X-DRAIS-Event:       <event_type>
X-DRAIS-Delivery-Id: <numeric webhook_deliveries.id>
X-DRAIS-Signature:   t=<unix_seconds>,v1=<hex_hmac_sha256>
Body:                <event payload, JSON>
```

Signature recipe (consumer side):
```
expected = HMAC_SHA256(subscription.secret, `${t}.${rawBody}`).toHex();
if (!timingSafeEqual(v1, expected))                    -> reject
if (Math.abs(now_unix_seconds - t) > 300)              -> reject (5-minute window)
```

Retries: exponential backoff `[30s, 2m, 10m, 30m, 2h, 6h]`. Maximum 6
attempts. After the 6th failure the delivery moves to `status='dead'` and is
not retried automatically. Manual requeue via
`POST /webhooks/{id}/deliveries/{deliveryId}/retry`.

Receiver contract: 2xx within 10 seconds = success. Any other response, or a
timeout, counts as failure.

### 1.9 Identifiers

- The only school identifier ever exposed in payloads, URLs, or events is
  `external_id` — an opaque UUID string. The internal numeric `schools.id`
  is server-only.
- Webhook IDs (`subscription.id`) and event IDs (`platform_events.id`) are
  numeric and stable. They are public identifiers within v1.
- Audit row IDs are also numeric and public within v1, used for pagination.

---

## 2. Versioning policy

### 2.1 Allowed in v1 (non-breaking)

- Adding new endpoints under `/api/platform/v1/...`
- Adding new fields to response bodies
- Adding new event types
- Adding new error codes
- Adding new scopes
- Adding new query parameters (with safe defaults)
- Performance / index improvements
- Bug fixes that align behavior with this document

### 2.2 Forbidden in v1 (would require v2)

- Removing any endpoint, field, error code, event, or scope listed above
- Narrowing a field's type (e.g. `string | null → string`)
- Repurposing an error code or event name
- Changing HTTP method on an existing path
- Changing the response envelope shape
- Changing pagination shape
- Changing the webhook signature scheme

### 2.3 Deprecation procedure (when v2 ships)

1. v2 ships at `/api/platform/v2/...`.
2. v1 endpoints add response header `Deprecation: true` and
   `Sunset: <RFC 1123 date at least 180 days out>`.
3. `ops` exposes per-consumer v1 traffic share.
4. After the sunset date, v1 returns `410 Gone` with body
   `{"success":false,"error":{"code":"VERSION_RETIRED","message":"v1 retired on <date>; migrate to v2"}}`.

There is no silent deprecation. There is no v1 endpoint that simply changes
meaning.

---

## 3. Idempotency contract

### 3.1 Replay protection

All mutation routes (`POST /suspend`, `POST /reactivate`, `PATCH /schools/{id}`,
`PUT /subscriptions/{id}`) accept the optional header:

```
X-Idempotency-Key: <opaque string, <= 128 chars>
```

- If the key has not been seen, the request is processed and the response is
  cached for that `(key_id, idempotency_key)` pair.
- If the key HAS been seen with the **same** request body (hashed
  method+path+body), the cached response is returned with header
  `X-Idempotent-Replay: true`.
- If the key has been seen with a **different** body, the request is rejected
  with `409 CONFLICT` and code `CONFLICT`.

### 3.2 Natural idempotency on state transitions

Suspend and reactivate are also semantically idempotent at the resource
level: a school that is already suspended returns
`{ status: 'suspended', already: true }` without re-emitting events from the
state-machine perspective. (See §6.1 for the concurrency caveat.)

### 3.3 Webhook delivery dedup

Two safeguards:
- **At enqueue:** unique constraint on `(subscription_id, event_id)` —
  re-emitting the same event for the same subscription is silently ignored.
- **At consumer:** the `X-DRAIS-Delivery-Id` header is unique per delivery
  attempt; consumers SHOULD dedup on it.

Retries reuse the same `Delivery-Id` and the same signature inputs (the
timestamp `t` is set at the original emit and is re-signed on each retry —
consumers MUST therefore verify against the body, not the wall clock of the
retry).

---

## 4. Tenant isolation contract

| Boundary | Mechanism |
|---|---|
| Per-school | `external_id` UUID is the only school identifier; numeric `schools.id` never exposed |
| Per-consumer (webhooks) | `GET/POST/PATCH/DELETE /webhooks*` filter by `consumer = ctx.consumer` |
| Per-consumer (audit/ops) | Documented as cross-consumer-visible to keys with `audit:read` (see §6.2) |
| Per-PII | Aggregates only on `/analytics`; per-school detail on `/usage` requires explicit `external_id` |

Cross-tenant write attempts (calling `/schools/<foreign_id>/suspend`) are
prevented by the URL → row lookup using `external_id`, which is a UUID and
not enumerable.

---

## 5. Observability contract

Every request, including 4xx and 5xx, writes one `platform_api_audit` row:

| Column | Always populated? |
|---|---|
| `request_id` | YES |
| `key_id` | YES if auth succeeded; NULL on bad/missing token |
| `consumer` | YES if auth succeeded |
| `method`, `path`, `status_code`, `ip`, `created_at` | YES |
| `response_ms` | YES on completed requests |
| `error_code` | YES on non-2xx |
| `school_id` | YES when the route resolved a school |
| `idempotency_key` | YES when the consumer sent one |
| `payload_bytes` | YES on mutations |

The `X-Request-Id` returned to the consumer matches the audit row's
`request_id`. This is the cross-system join key.

Every state mutation also writes a `platform_events` row whose `payload.by`
field records `{consumer, keyId}` — answering "which key did this" without
needing the audit table.

---

## 6. Known, documented behaviors (NOT bugs)

These are deliberate v1 behaviors that consumers must accommodate:

### 6.1 Event-emit race under concurrent state mutations

The suspend / reactivate handlers read the current school state, then write
the new state, then emit an event. Under N truly-concurrent calls without
idempotency keys, all N may emit the event (only one actually changes state;
the others are no-ops at the row level).

**Consumer guidance:** always send `X-Idempotency-Key` on mutations.
Idempotent replay collapses duplicates to one event. Without an idempotency
key, consumers MUST dedup webhook events on `X-DRAIS-Delivery-Id` (which is
already guaranteed unique per delivery attempt).

This is an accepted v1 tradeoff. A future hardening pass may introduce
conditional UPDATEs to collapse the event-emit race at the source; doing so
is non-breaking.

### 6.2 `audit:read` and `ops` are cross-consumer visible

A key with `audit:read` can see audit rows and ops counters for the entire
platform (across all consumers), not only its own activity. This is
deliberate: `audit:read` is intended for the operator-side `internal_ops`
key, not for external consumers.

**Operator guidance:** do not grant `audit:read` to external consumers
unless cross-consumer visibility is desired.

### 6.3 Webhook receiver responsibility

DRAIS guarantees at-least-once delivery, NOT exactly-once. Receivers must
be idempotent on `X-DRAIS-Delivery-Id`. A receiver that times out *after*
processing successfully will be retried; it must detect the duplicate
delivery and ack with 2xx without reprocessing.

### 6.4 Rate limiter is sliding-minute, DB-backed

Rate limits reset on minute boundaries (wall clock). A consumer that
hammers requests across a minute boundary may briefly burst over the
per-minute ceiling within a sub-second window. Limits remain enforced over
any 60-second sliding interval.

### 6.5 No exactly-once event ordering across event types

Events for the same school may arrive out of order under retry storms
(e.g. `subscription.changed` then `school.suspended` may deliver in either
order). Consumers MUST drive their own state from the current payload, not
from event ordering. Use `GET /schools/{external_id}` to reconcile if the
event payload is ambiguous.

---

## 7. Breaking-change governance

Any proposal that violates §2.2 must:

1. Open an architecture review document inside DRAIS.
2. Reserve `/api/platform/v2/<endpoint>` and implement alongside v1.
3. Announce via webhook event `platform.version.deprecated` to all active
   subscriptions, with payload `{ from: 'v1', sunset_at: <ISO> }`.
4. Wait the full sunset window (≥ 180 days).
5. Switch v1 to `410 Gone`.

No exceptions. No silent breaks. No "we'll add it back later."

---

## 8. Frozen artifacts (commit them; treat as load-bearing)

- `migrations/platform_api_foundation.sql`
- `migrations/platform_api_hardening.sql`
- `src/lib/platform/scopes.ts`        — scope enum
- `src/lib/platform/contracts.ts`     — TypeScript types
- `src/lib/platform/events.ts`        — event type enum
- `src/lib/platform/response.ts`      — envelope + error code enum
- `docs/PLATFORM_API.md`              — narrative reference
- `docs/PLATFORM_READINESS.md`        — operational checklist
- `docs/PLATFORM_CONTRACT_FREEZE.md`  — THIS file

Any PR that touches these files must reference this document and either
(a) prove the change is in §2.1, or (b) declare a v2 migration plan per §7.
