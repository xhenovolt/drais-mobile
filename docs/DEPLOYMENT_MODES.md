# The three ways to run DRAIS Mobile

The app talks to a **DRAIS server**. Where that server runs is a deployment
choice, not a code change — the app is identical in both modes and switches
between them from its own UI.

## Mode C — direct to TiDB, no server at all

```
App  ──TLS──▶  TiDB Cloud
```

The app **is** the backend. It opens the database connection, runs the queries
and applies the rules itself. No server process, no address to enter, no
connect screen — the same topology as the Next.js desktop build, where the API
routes execute inside the executable.

### Turning it on

Direct mode exists exactly when a `drais.env` file is found at startup. There
is no setting and no toggle: presence of the file *is* the mode.

```ini
# drais.env
TIDB_HOST=gateway01.eu-central-1.prod.aws.tidbcloud.com
TIDB_PORT=4000
TIDB_USER=xxxxxxxx.root
TIDB_PASSWORD=xxxxxxxx
TIDB_DB=drais
```

Searched in order, highest priority first:

| # | Location | Platform |
|---|---|---|
| 1 | beside the executable | desktop |
| 2 | the working directory | desktop |
| 3 | the app support directory | all — writable at runtime |
| 4 | `assets/drais.env`, bundled into the build | all |

**For an APK, use 4.** There is no "beside the executable" on Android, and
path 3 would mean pushing a file to every device. Put `drais.env` in
`assets/` before building and the installed APK works with nothing to place —
install, open, sign in. No server to start, no address to enter.

Paths 1–3 still win over the bundled asset, so a single device can be
repointed without a rebuild — the same precedence `electron/config.cjs` uses.

Restart the app. The log says `Direct database mode active — no DRAIS server
required.` and it goes straight to login.

Delete the file and it returns to Mode A or B on the next launch.

### Why the credential is in a file and not the build

`--dart-define` values are compiled into the binary, and an APK or desktop
bundle is an archive anyone can open. A provisioned file is placed per
installation, so rotating the password does not mean re-releasing the app —
the same reasoning as `userData/drais.env` in the DRAIS desktop build.

### Read this before shipping Mode C

With no server, **tenant isolation and permission checks run on the device**.
The code applies the same rules the server does — `school_id` always comes from
the validated session row, never from the UI — but it is discipline, not a
boundary. Anyone who can read the config or modify the app reaches the whole
database, for every school.

That is a reasonable trade on **a machine the school controls**: an office
desktop, a dedicated tablet. It is not a reasonable trade on a teacher's
personal phone, which leaves the building and can be lost or sold.

**Recommended:** Mode C for school-controlled desktops, Mode A for handsets.
The same build does both; only the presence of `drais.env` differs.

## Mode A — hosted DRAIS (the normal case)

```
Phone / desktop  ──HTTPS──▶  hosted DRAIS  ──▶  TiDB Cloud
```

Run the app. On the connect screen enter your hosted address, e.g. `drais.pro`.
That is all.

**On a fresh computer this needs nothing but Flutter.** No `server/`, no
`.env`, no Node.js, no npm, no database credentials on the machine. Clone the
repo, `flutter pub get`, `flutter run`.

This is what ships to schools. Nobody installs a server; nobody holds a
credential.

## Mode B — your own DRAIS server

```
Phone  ──HTTP/LAN──▶  DRAIS Server (Dart, this repo)  ──TLS──▶  TiDB Cloud
```

Run `server/` yourself — on your laptop for development, or on a school machine
so its devices work over the LAN.

```bash
cd server && cp .env.example .env    # TiDB credentials go HERE, on the server
dart run bin/server.dart
```

Then connect the app to `127.0.0.1:8080` (same machine) or
`192.168.1.50:8080` (another device on the network).

Use it for developing against the API, for a school that wants its own server,
or as a fallback if the hosted deployment is unreachable.

## Which one am I in?

The login screen names the connected host under the sign-in button, with a lock
icon for HTTPS and a network icon for a LAN address. In Mode C there is no host
line, because there is no server. The diagnostics screen shows the resolved
mode either way.

## Switching

| Where | How |
|---|---|
| Login screen | **Change server** under the host name |
| Dashboard | ⋮ menu → **Change server** |

Switching signs you out first — while the old address is still known, so the
session is properly invalidated on the server that issued it — then clears the
stored address and returns to the connect screen. The response cache is cleared
too: the next server may be a different school entirely, and its data must not
mix with the last one's.

## Where credentials live

| Mode | Credential location |
|---|---|
| A — hosted | **Nowhere on the device.** The hosted server holds it. |
| B — own server | `server/.env`, on the machine running the server |
| C — direct | `drais.env`, on every device running the app |

Mode C is the only one that puts a database credential on an end-user device.
That is the whole of its cost, and the reason for the recommendation above.

**A bundled `assets/drais.env` is the strongest form of that cost.** An APK is
a zip file: `unzip -p app.apk assets/flutter_assets/assets/drais.env` prints
the password. No rooting, no tooling. Ship it only to devices the school
controls, and rotate the credential if such a build ever leaves them.

`server/.env` is gitignored. Never copy its values into `env/*.json`: those are
compiled into the binary, and an APK is a zip file.

## A build can ship a default server

Setting `DRAIS_API_BASE_URL` in `env/production.json` means users never see the
connect screen — the app starts at login, already pointed at your hosted
deployment. **Change server** still works, so a school can move to its own
server without a new build.

Leave it unset and the app asks on first launch. Both are valid; there is no
localhost default in either case.
