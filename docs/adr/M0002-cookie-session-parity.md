# M0002: Mobile authenticates with the platform's session cookie, not a token

- **Status:** Accepted
- **Date:** 2026-08-05
- **Affects:** `lib/core/storage/cookie_store.dart`, `lib/core/network/interceptors/`, `/api/auth/*`

## Problem

Every Flutter authentication tutorial describes the same design: log in, receive a JWT access token and a refresh token, store them, send `Authorization: Bearer`, and refresh on 401. The brief asks for token storage and token refresh.

DRAIS LongTerm does not work that way, and building the tutorial version would mean adding a second authentication mechanism to the platform for the benefit of one client.

## Context

What the school authentication path actually does, read from the source:

- `POST /api/auth/login` verifies the password with bcrypt, generates `randomBytes(32).toString('hex')`, inserts a row into `sessions`, and sets an **`HttpOnly`, `SameSite=Lax`, 7-day** cookie named `drais_session`. It also sets `drais_school_id` and `drais_role` as readable cookies for the Edge middleware.
- `getSessionSchoolId()` in `src/lib/auth.ts` validates that token against the `sessions` table on **every** protected request, joining through to `users` and `schools` and re-checking school status and subscription each time.
- `sessions.last_activity_at` is updated on each request. **`expires_at` is not extended.** There is no sliding renewal.
- There is **no refresh endpoint anywhere in the school auth path.** `JWT_SECRET`, `JWT_EXPIRES_IN`, `REFRESH_SECRET` and `REFRESH_TOKEN_EXPIRES_IN` are present in `.env` but unused by it — vestigial configuration.

So the session is an opaque server-side record with a hard seven-day life. When it dies, the only recovery is a new sign-in.

The brief is explicit: *"Do NOT redesign authentication unless absolutely necessary."*

## Decision

**DRAIS Mobile is a cookie client.** It stores and replays `drais_session` exactly as a browser would, and it consumes `/api/auth/login`, `/api/auth/me` and `/api/auth/logout` unchanged.

1. **`CookieInterceptor`** attaches stored cookies to every request and captures `Set-Cookie` from every response — including error responses, because `/api/auth/logout` clears cookies while some failure paths still return one.
2. **`CookieStore` persists the jar in the platform keystore**, not in files. `drais_session` is a seven-day bearer credential; `PersistCookieJar` from `package:cookie_jar` writes plaintext files to the documents directory, which is the wrong place for it. This is why that package is not used.
3. **There is no token refresh, because there is nothing to refresh.** `SessionInterceptor` detects a dead session — by status *and* by the `success:false` envelope, since LongTerm returns some 401-equivalents with HTTP 200 — and raises exactly one global sign-out.
4. **`onSessionInvalidated` is the documented seam.** If LongTerm ever grows a refresh endpoint, that callback is where the attempt goes, and nothing above it changes.
5. **Session restoration is `/api/auth/me`**, which is also the only honest test of session validity — the cookie's presence proves nothing, since the server may have invalidated the row.

## Alternatives considered

**Add a mobile-only bearer-token endpoint to LongTerm.** The conventional answer, and it would give textbook refresh semantics. Rejected as the most expensive option available: it means two authentication mechanisms on the server, two code paths through `getSessionSchoolId`, two ways for the tenant-isolation guarantee to be wrong, and a second credential format to audit. [ADR-0008](../platform/0008-two-auth-systems.md) exists because the platform already found that having two auth systems is a serious, deliberate cost — adding a third for client convenience inverts that reasoning. This project exists to prevent divergence; forking the auth model on day one would be the largest divergence available.

**Use `package:cookie_jar` with `PersistCookieJar`.** Standard, well-tested, and would have taken an afternoon. Rejected on credential storage alone: it persists to plaintext files. `WebviewCookieManager` was rejected for the same reason plus a webview dependency.

**Store the session token and send it as a custom header.** Requires a server change to read it, so it is the "add a second mechanism" option wearing a smaller hat.

**Keep the session in memory only.** Most secure, and unusable: every cold start would demand a password. Teachers open this app several times a day on the school run.

## Trade-offs

- **A seven-day hard expiry means an unavoidable re-login every week.** No client-side design can change this; it is a server property. Users will experience it as "the app logs me out on Mondays".
- **Cookie handling is code we own.** `CookieStore` parses `Set-Cookie` itself, so RFC 6265 edge cases are our problem. Mitigated by only ever talking to one origin whose cookies are set by code we can read.
- **`onSessionInvalidated` is a guarded singleton.** A burst of parallel 401s must produce one sign-out, not twelve. That guard has to be reset on the next successful sign-in, and forgetting to would leave the app unable to detect the *next* expiry — hence `resetSessionGuard()`.
- **We inherit whatever the platform's session security is.** If the seven-day lifetime is ever judged too long for a device that leaves the school, that is a platform conversation, not a mobile one.

## Consequences

- The mobile app cannot be signed in when a browser could not be, and vice versa. One session model, one set of rules.
- No server change was required to ship mobile authentication.
- Sessions appear in `/api/auth/sessions` alongside web sessions, with `device_info` parsed from our `User-Agent`, so a user can see and revoke their phone from the web app.
- Audit rows in `audit_logs` attribute mobile activity correctly, because the app sends a distinguishable `User-Agent` and `X-DRAIS-Client: mobile`.

## Future considerations

The change that would justify revisiting this is **server-side**: if LongTerm adds sliding session renewal or a refresh endpoint for its own reasons, mobile should adopt it immediately — the seam is already in place. Conversely, if a shorter session lifetime is ever wanted for devices that leave school premises, the right implementation is a server policy keyed on the client type, not a mobile-only mechanism.
