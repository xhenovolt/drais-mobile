# Running and debugging DRAIS

Two processes: the **Dart server** (talks to TiDB) and the **Flutter app** (talks to the server). Start the server first — the app will show its connect screen either way, but there is nothing to sign in to until the server is up.

## One-time setup

```bash
cd server && dart pub get && cp .env.example .env    # fill in TIDB_*
cd .. && flutter pub get
```

## Running

### Terminal 1 — the server

```bash
cd server
dart run bin/server.dart
```

```
DRAIS Server starting…
  ✔ TiDB reachable (327ms)
  ✔ Listening on http://0.0.0.0:8080
```

If it exits instead, it is telling you why — a missing `TIDB_*` value (exit 78) or an unreachable database (exit 69). It deliberately refuses to start rather than accept traffic it cannot serve.

### Terminal 2 — the app

```bash
flutter run -d linux --dart-define-from-file=env/development.json
```

### Then connect

The app opens on the **connect screen**, because no build ships a default server address. Enter:

| Where the app runs | Address |
|---|---|
| Linux desktop, same machine | `127.0.0.1:8080` |
| Android emulator | `10.0.2.2:8080` |
| Physical phone on the same Wi-Fi | `192.168.1.135:8080` |

It probes `/api/health` and confirms the address is genuinely DRAIS before storing it, then moves to the login screen. The address is remembered — you only do this once per install.

Sign in with any real DRAIS account. The same credentials as the web app: the Dart server verifies the same bcrypt hashes.

## Debugging in VS Code

`.vscode/launch.json` defines three configurations and one compound.

**Run → "DRAIS — server + app"** starts both together, with breakpoints working in each. Stopping one stops both.

Breakpoints worth setting first time through:

| File | Why |
|---|---|
| `server/lib/routes/auth_routes.dart` → `_login` | See the row that comes back from `users` |
| `server/lib/auth/password.dart` → `verify` | Confirm the hash prefix and the verify result |
| `lib/features/auth/data/repositories/auth_repository_impl.dart` → `login` | The client's two-call flow |
| `lib/core/network/api_client.dart` → `_handleResponse` | What the envelope parsed to |

## Watching what happens

**Server** logs one line per request, with the client's correlation id when present:

```
[2026-08-06T10:59:01.460041] 401 POST /api/auth/login (540ms) req=mob-m9x2k1-a7f3bc91
```

It never logs bodies or headers — those carry passwords and the session cookie.

**App** logs through `AppLogger` to the Dart DevTools console, tagged `DRAIS`. In development it includes request and response bodies, redacted. The same `req=` id appears on both sides, so a client failure can be matched to its server line.

**Diagnostics screen** — from the login screen or the dashboard's bug icon. Shows the resolved server, where it came from, timeouts, session state, connectivity, and a live `/api/health` probe. It is the fastest way to answer "is it the app or the server".

## Testing without the app

```bash
# Health
curl -s http://127.0.0.1:8080/api/health | jq

# Login — keep the cookie jar
curl -s -c /tmp/drais.jar -X POST http://127.0.0.1:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@school.ug","password":"your-password"}' | jq

# Identity, using that session
curl -s -b /tmp/drais.jar http://127.0.0.1:8080/api/auth/me | jq

# Sign out
curl -s -b /tmp/drais.jar -X POST http://127.0.0.1:8080/api/auth/logout | jq
```

If `/api/auth/me` returns your user, roles and permissions, the migration works end to end.

## When something goes wrong

| Symptom | Cause |
|---|---|
| App can't reach the server | Wrong address for the target — see the table above. `127.0.0.1` from an emulator means the *emulator itself*. |
| "Signed in, but the session could not be stored" | `SECURE_COOKIES=true` over plain HTTP. A `Secure` cookie is never returned over HTTP. Set it to `false` for local and LAN. |
| Login returns 401 for a known-good password | Check the hash prefix in `users`. `$2a$`, `$2b$` and `$2y$` are handled; anything else is not bcrypt. |
| "Unexpected response from the server" | Something answered that is not DRAIS — a proxy, a captive portal, or the wrong port. |
| Server exits 78 at startup | A `TIDB_*` value is missing from `server/.env`. |
| Server exits 69 at startup | TiDB unreachable — network, or credentials rotated. |
| Server exits 73 at startup | Port already taken, usually an earlier run. `pkill -f "bin/server.dart"`, or `PORT=8081 dart run bin/server.dart`. |
| Only paginated endpoints fail, only in production | The TiDB `LIMIT ?` trap. Use `Database.limitClause()`. See ADR-0010. |
| Linux build fails in `json.hpp` or `libsecret-1 not found` | An old `flutter_secure_storage`. v10.3.1+ needs no system packages; run `flutter pub get`. |

## Verifying before you push

```bash
flutter analyze && flutter test          # app:    58 tests
cd server && dart analyze && dart test   # server: 18 tests
```
