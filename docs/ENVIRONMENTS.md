# Environment configuration

Switching DRAIS Mobile between Development, Staging, QA and Production requires changing **one thing**: which file is passed to `--dart-define-from-file`. No source edit, no branch, no conditional compilation.

```bash
flutter run                        --dart-define-from-file=env/development.json
flutter build apk --release        --dart-define-from-file=env/production.json
flutter build appbundle --release  --dart-define-from-file=env/production.json
```

Everything except the **server address** is fixed at build time.

## Server selection

**There is no default server address, and no localhost anywhere.**

The app can do this because every screen is compiled into the APK. Unlike the Next.js client — whose HTML does not exist until a server renders it, which is why it needs `localhost:3000` before you can see a login form — this app opens, draws and navigates with no server at all. The server is needed for *data*, not for pixels.

Resolution order:

1. **A server the user chose**, stored on the device.
2. **`DRAIS_API_BASE_URL`**, if the build names one. A production release normally does, pointing at the hosted deployment, so nobody is ever asked.
3. **Nothing** — the app shows the connect screen when data is first needed.

There is no fourth step. Guessing an address is what previously pointed builds at a developer's machine.

### Two kinds of address work

| Deployment | Example | Notes |
|---|---|---|
| Hosted DRAIS | `drais.pro` | https required |
| A school's own DRAIS server | `192.168.1.50:3210` | Plain http accepted on a private network — a LAN server has no certificate, and the desktop build already binds `0.0.0.0:3210` for exactly this |

From the phone's side these are the same thing: an address. Whether that server runs against TiDB Cloud or a local MySQL ([ADR-0010](platform/0010-dual-database-mode.md)) is the *server's* business and completely invisible here. **The app never chooses, sees or reaches a database.**

### The address is verified before it is stored

`ServerProbe` calls `/api/health` and checks the response is actually DRAIS — a wrong address usually *does* answer, with a router admin page or a captive portal, and "connection successful" against a home router would be worse than useless. It also reports whether that DRAIS server can reach its own database, so a user is told *"this server cannot reach its database"* rather than concluding their password is wrong.

Rejected outright: cleartext http to a public host (the session cookie is a seven-day bearer credential), and any address pointing at the device itself — nothing on a phone hosts DRAIS.

## Variables

All are optional; every one has a default in `AppConfig.fromEnvironment()`.

| Variable | Default | Purpose |
|---|---|---|
| `DRAIS_ENV` | `development` | `development` \| `staging` \| `qa` \| `production`. Unrecognised values fall back to `development` — the least-privileged default. |
| `DRAIS_API_BASE_URL` | **none** | Optional *default* server origin. Absent means the app asks on first launch — see "Server selection". |
| `DRAIS_APP_NAME` | `DRAIS` | Display name. Mirrors `NEXT_PUBLIC_APP_NAME`. |
| `DRAIS_CONNECT_TIMEOUT_MS` | `15000` | TCP/TLS establishment. |
| `DRAIS_RECEIVE_TIMEOUT_MS` | `30000` | Between response bytes. |
| `DRAIS_SEND_TIMEOUT_MS` | `60000` | Request body streaming. Generous — uploads on a Ugandan mobile network are the slow path this app is designed around. |
| `DRAIS_MAX_RETRIES` | `2` | Retries for **idempotent methods only** (`GET`/`HEAD`/`OPTIONS`). |
| `DRAIS_PAGE_SIZE` | `25` | Default `limit` on list endpoints. |
| `DRAIS_MAX_FILE_SIZE` | `10485760` | Client-side upload ceiling. Mirrors `MAX_FILE_SIZE`. |
| `DRAIS_SESSION_TIMEOUT_MINUTES` | `60` | Idle-warning hint. **Not** authoritative — the server's 7-day `sessions.expires_at` is. |
| `DRAIS_LOG_NETWORK` | `!production` | Whether requests and responses are logged. |
| `DRAIS_ALLOW_INSECURE_HTTP` | `!production` | Whether `http://` origins are permitted. |

## Mapping from the LongTerm `.env`

LongTerm's `.env.local` holds around sixty variables. **Almost none belong in a mobile binary**, because anything in an APK is readable by anyone holding the APK.

### Reused

| LongTerm | Mobile |
|---|---|
| `NEXT_PUBLIC_APP_URL` | `DRAIS_API_BASE_URL` (optional default only) |
| `NEXT_PUBLIC_APP_NAME` | `DRAIS_APP_NAME` |
| `NEXT_PUBLIC_APP_VERSION` | `pubspec.yaml` + `AppVersion` |
| `MAX_FILE_SIZE` | `DRAIS_MAX_FILE_SIZE` |
| `SESSION_TIMEOUT_MINUTES` | `DRAIS_SESSION_TIMEOUT_MINUTES` |
| `NODE_ENV` / `VERCEL_ENV` | `DRAIS_ENV` |

### Never, under any circumstances

`TIDB_HOST`, `TIDB_USER`, `TIDB_PASSWORD`, `TIDB_DB`, `TIDB_CONNECTION_STRING`, `LOCAL_MYSQL_*`, `DB_*`, `MYSQL_*`, `DATABASE_MODE`, `DRAIS_ALLOW_LOCAL`, `JWT_SECRET`, `REFRESH_SECRET`, `ENCRYPTION_KEY`, `BCRYPT_ROUNDS`, `CONTROL_API_KEY`, `CONTROL_API_SECRET`, `JETON_API_KEY`, `CRON_SECRET`, `ADMIN_SECRET`, `DEVICE_CLAIM_SECRET`, `CLOUDINARY_API_SECRET`, `AFRICASTALKING_*`, `AT_API_KEY`, `SMS_API_KEY`, `WHATSAPP_API_KEY`, `SMTP_*`.

**The mobile app never opens a database connection.** Cloudinary uploads, SMS dispatch and every other credentialed operation happen server-side, reached through the API. `AppConfig` reads none of these and a review must reject any change that adds one.

## Validation

`AppConfig.validate()` runs during `bootstrap()`, before anything else can use the configuration. It rejects:

- a malformed `DRAIS_API_BASE_URL` **if one is given** (absence is valid);
- cleartext `http://` where `DRAIS_ALLOW_INSECURE_HTTP` is false — the session cookie would travel unencrypted;
- a **production** build pointed at `localhost`, `127.0.0.1`, `10.0.2.2`, `0.0.0.0` or a `192.168.*` address;
- a `DRAIS_PAGE_SIZE` outside 1–200.

In production a failure is **fatal**: the app shows a configuration-error screen and does not start. Outside production it logs a warning and continues, because a developer pointing at a laptop over http is doing so on purpose.

A loud failure at launch is far cheaper than a quiet one in a school.

## Non-production builds are visibly marked

- a corner banner naming the environment;
- the environment and API origin on the login screen;
- a link to the diagnostics screen (`/diagnostics`), which shows build metadata, timeouts, session state, connectivity, and a live `/api/health` probe.

The commonest support question during a rollout is *"why can't I sign in"*, and the commonest answer is *"you installed the staging build"*. One screenshot settles it.

## Adding a variable

1. Add the field, default and documentation to `AppConfig`.
2. Add it to all four files in `env/`.
3. Add a row to the table above.
4. If it constrains a request, extend `AppConfig.validate()`.
5. **Confirm it is not a secret.** If it would be dangerous in an attacker's hands, it belongs on the server.
