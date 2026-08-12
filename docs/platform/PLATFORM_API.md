# DRAIS Platform API — v1

A versioned, scope-gated, audit-logged HTTP surface for external orchestration
systems (JETON and future Xhenvolt systems: Xhaira, Consty, Jorc, Xheton).

**Layering rule.** This layer is strictly separate from the tenant-facing
`/api/*` routes. Platform endpoints never read the session cookie, never trust
a `school_id` query string, and never return per-learner / per-staff PII unless
the scope on the calling key explicitly grants it.

Base URL: `https://<drais-host>/api/platform/v1`

---

## 1. Authentication

Every request requires a bearer token issued by the DRAIS super-admin via
`POST /api/admin/platform-keys` (cookie-authenticated, super-admin only).

```
Authorization: Bearer pk_live_<keyId>.<secret>
```

(`X-Api-Key: <keyId>.<secret>` is also accepted for clients that cannot set
`Authorization`.)

The token is shown **once** at issue time. Store it securely.
Tokens are bcrypt-hashed at rest; lost tokens cannot be recovered, only revoked
and reissued.

### Scopes

A token grants only the scopes selected at creation:

| Scope | Capability |
|---|---|
| `health:read`         | `/health` |
| `schools:read`        | List/get schools, subscription read |
| `schools:write`       | Update, suspend, reactivate schools |
| `subscriptions:read`  | `/subscriptions/{external_id}` GET |
| `subscriptions:write` | `/subscriptions/{external_id}` PUT |
| `usage:read`          | `/usage` |
| `analytics:read`      | `/analytics` |
| `events:read`         | `/events` |
| `webhooks:manage`     | `/webhooks` CRUD |
| `audit:read`          | `/audit` |

Insufficient scope → `403 INSUFFICIENT_SCOPE`.

### IP allowlist (optional, recommended for production keys)

Set `allowed_ips: ["1.2.3.4"]` at creation to lock the key to a fixed source.
Mismatched IP → `403 IP_NOT_ALLOWED`.

### Rate limiting

Default 600 requests/minute/key (configurable per key).
Headers on every response:

```
X-RateLimit-Limit:     600
X-RateLimit-Remaining: 482
X-RateLimit-Reset:     1737640920
```

Exceeded → `429 RATE_LIMITED` + `Retry-After`.

### Audit

Every platform request — success or failure, including 401/403/429 — is row-logged
to `platform_api_audit` (request_id, key_id, consumer, method, path, status, ip,
ms, error_code, school_id). Readable through `GET /audit` (scope `audit:read`).

---

## 2. Response envelope

All responses:

```jsonc
// success
{ "success": true, "data": { ... } }

// failure
{ "success": false, "error": { "code": "NOT_FOUND", "message": "...", "details": {...} } }
```

Headers on every response:

```
X-Request-Id:  <uuid>     // echo this when reporting issues
X-Api-Version: v1
Cache-Control: no-store
```

### Error codes

| Code                    | HTTP | Meaning |
|---|---|---|
| `UNAUTHORIZED`          | 401 | Missing/invalid token |
| `KEY_REVOKED`           | 401 | Token was revoked |
| `KEY_EXPIRED`           | 401 | Token expired |
| `IP_NOT_ALLOWED`        | 403 | Source IP not on allowlist |
| `INSUFFICIENT_SCOPE`    | 403 | Token lacks required scope |
| `NOT_FOUND`             | 404 | Resource missing |
| `BAD_REQUEST`           | 400 | Malformed input |
| `CONFLICT`              | 409 | Idempotency hash mismatch |
| `RATE_LIMITED`          | 429 | Rate limit exceeded |
| `SERVER_ERROR`          | 500 | Unexpected |
| `SERVER_MISCONFIGURATION` | 503 | Missing env / setup |

---

## 3. Endpoints

### Health

```
GET /health
Scope: health:read
```

Lightweight liveness check; also reports DB connectivity.

### Schools

```
GET    /schools                              schools:read   # cursor-paginated
GET    /schools/{external_id}                schools:read
PATCH  /schools/{external_id}                schools:write  # name|email|phone
POST   /schools/{external_id}/suspend        schools:write  # { reason? }
POST   /schools/{external_id}/reactivate     schools:write
```

`schools.id` (the internal numeric PK) is **never** exposed. `external_id` is the
only identifier external systems see.

Pagination: `?limit=50&cursor=<id>&status=active&search=foo`.

### Subscriptions

```
GET /subscriptions/{external_id}    subscriptions:read
PUT /subscriptions/{external_id}    subscriptions:write
```

PUT mutable fields:
`subscription_status` (`active|inactive|trial|expired`),
`subscription_plan` (`none|trial|monthly|yearly`),
`trial_start_date`, `trial_end_date`,
`subscription_start_date`, `subscription_end_date`.

Emits `subscription.changed`.

### Usage

```
GET /usage?school={external_id}&since_days=30   usage:read
```

If `school` omitted → platform-wide totals. Returns:

```json
{
  "school": "ext_abc...",
  "window_days": 30,
  "learners": 412,
  "staff": 28,
  "sms_sent": 1840,
  "sms_sent_24h": 62,
  "active_sessions": 9,
  "api_payload_bytes": 0
}
```

### Analytics

```
GET /analytics    analytics:read
```

Aggregate platform metrics — never leaks per-school PII. Returns tenant counts,
12-month growth, plan breakdown, 30-day SMS volume, 7-day active tenants.

### Events

```
GET /events?event_type=school.suspended&since=2026-05-01&limit=50&cursor=<id>
Scope: events:read
```

Read the canonical event log. Same data fanned out to webhooks.

#### Event types

| Type | Fired when |
|---|---|
| `school.created`       | New tenant provisioned |
| `school.updated`       | Fields changed via PATCH |
| `school.suspended`     | `/suspend` invoked |
| `school.reactivated`   | `/reactivate` invoked |
| `school.deleted`       | Soft-deleted |
| `subscription.changed` | Plan/status/dates updated |
| `subscription.expiring`| 7 days before expiry (planned) |
| `subscription.expired` | Auto-marked expired (planned) |
| `payment.received`     | Tenant payment captured (planned) |
| `sms.balance.low`      | Provider balance below threshold (planned) |
| `learner.limit.exceeded` | Tenant exceeds plan capacity (planned) |
| `tenant.health.degraded` | Heartbeat/error budget breached (planned) |

### Webhooks

```
GET    /webhooks                  webhooks:manage
POST   /webhooks                  webhooks:manage
GET    /webhooks/{id}             webhooks:manage
PATCH  /webhooks/{id}             webhooks:manage
DELETE /webhooks/{id}             webhooks:manage
```

POST body:

```json
{ "url": "https://jeton.xhenvolt.com/hooks/drais",
  "event_types": ["school.*", "subscription.changed"] }
```

`["*"]` subscribes to all events.

**Signing.** Each delivery includes:

```
X-DRAIS-Event:        school.suspended
X-DRAIS-Delivery-Id:  84219
X-DRAIS-Signature:    t=1737640920,v1=<hex-hmac-sha256>
```

Verify by computing `HMAC_SHA256(secret, "<t>.<rawBody>")` and comparing in
constant time. The `secret` is returned **only at subscription creation**.

**Retries.** Non-2xx responses (or timeouts >10s) retry with exponential
backoff at 30s, 2m, 10m, 30m, 2h, 6h — then marked `dead`.

### Audit

```
GET /audit?key_id=pk_live_...&path=/api/platform/v1/schools&limit=100
Scope: audit:read
```

---

## 4. Idempotency (writes)

Send `X-Idempotency-Key: <uuid>` on any POST/PATCH/PUT.
Replays with the same key and identical body return the original response.
Replays with the same key and a *different* body return `409 CONFLICT`.

(Infrastructure present in `src/lib/platform/idempotency.ts`; per-route adoption
will be wired in P1 cleanup.)

---

## 5. Operational notes

### Webhook delivery worker

Deliveries are enqueued to `webhook_deliveries`. The worker route
`GET /api/cron/platform-webhooks` (protected by `CRON_SECRET` header) processes
up to 25 pending deliveries per invocation and prunes stale rate-limit buckets.

On the Vercel Hobby plan only one cron/day is allowed, so this route is not
scheduled by default. Wire it up on Vercel Pro (`*/1 * * * *`) or run it from an
external scheduler:

```
curl -H "Authorization: Bearer $CRON_SECRET" \
     https://<host>/api/cron/platform-webhooks
```

### Key management

Cookie-authenticated, super-admin only:

```
GET    /api/admin/platform-keys                 # list
POST   /api/admin/platform-keys                 # issue (returns token ONCE)
DELETE /api/admin/platform-keys?key_id=<keyId>  # revoke
```

### Versioning

URI-prefixed (`/api/platform/v1/...`). Breaking changes ship as `/v2` running in
parallel; `v1` is supported for a documented deprecation window.

---

## 6. Integration patterns for external orchestrators

These are descriptive only — DRAIS does not implement orchestrator UI.

1. **Provisioning a new tenant from outside DRAIS.** Use cookie-authenticated
   tenant onboarding routes already in `/api/admin/schools` (not platform).
   Then have JETON list tenants via `GET /schools`.
2. **Suspending non-paying tenants.** Receive `subscription.expired` webhook →
   call `POST /schools/{external_id}/suspend` with a reason.
3. **Cross-tenant dashboards in JETON.** Poll `GET /analytics` (cheap,
   pre-aggregated) for headline tiles; drill down via `GET /usage` per tenant.
4. **Real-time monitoring.** Subscribe to `["*"]` and persist into JETON's own
   event store; query the `GET /events` backfill on startup to catch up after
   downtime.
5. **Auditing operator actions.** Every JETON-triggered write writes a row to
   `platform_api_audit` keyed by `request_id`. JETON should log the same
   `request_id` on its side for join-on-incident.

---

## 7. Out of scope (this DRAIS release)

- Per-tenant billing capture (the `/api/payments/*` tenant routes own that
  pipeline; platform events surface it but DRAIS doesn't initiate billing).
- HMAC body signing on inbound platform requests (only outbound webhooks are
  signed today; inbound key-only auth is sufficient until a leaked-key incident
  motivates request signing).
- OAuth/service accounts (single-secret bearer is sufficient for the current
  internal-trust model).

---

## Appendix B — Additive endpoints (post-freeze, v1 non-breaking)

These were added after the freeze for the Jeton master-control use cases. They
are additive (new scopes, new endpoints, new response fields only) and do not
change any frozen path/shape.

### New scopes
| Scope | Capability |
|---|---|
| `staff:read`      | `GET /schools/{external_id}/staff` |
| `features:read`   | `GET /schools/{external_id}/features` |
| `features:write`  | `PUT /schools/{external_id}/features` |

### `GET /schools/{external_id}/staff`  (scope `staff:read`)
Staff directory: `{ name, staff_no, role, department, status }` per member.
Sensitive employment PII (salary, bank, NSSF, TIN) is never returned.

### `GET|PUT /schools/{external_id}/features`  (scopes `features:read` / `features:write`)
Read or remotely toggle per-school controls:
- `sms_enabled` — hard SMS kill-switch, enforced in the comm dispatcher, the
  notification drain, broadcast, and `/api/sms/send` (disabled ⇒ no SMS leaves).
- `modules` — `school_modules` flags (academics, finance, payroll, tahfiz,
  attendance, inventory, examinations, analytics, fingerprint_auth,
  intelligence, work_plans).

PUT body: `{ "sms_enabled"?: boolean, "modules"?: { "<code>": boolean } }`.
Emits a `school.updated` platform event with the applied changes.

### `GET /usage` — additive fields
- `storage`: `{ file_bytes, file_mb, file_count }` (Cloudinary/file storage from
  `documents.file_size`).
- `db_footprint`: `{ total_rows, by_table }` over curated high-volume,
  school-scoped tables.

### Fix: `GET /schools` now returns the real `external_id`
Previously returned `id AS external_id` (the internal numeric id), which both
violated the "never expose the internal numeric id" rule and broke list→detail
round-trips (detail routes filter the real `external_id`). Now returns the
stable `external_id`; the pagination cursor (internal `id`) was fixed alongside.
Suspending / acting on a school by the id from `GET /schools` now works.
