# DRAIS Mobile

A native Flutter client for the DRAIS school attendance platform.

DRAIS records attendance from **biometric devices**. A device sends a punch,
DRAIS works out who it belongs to, and a rule engine derives that person's
verdict for the day — present, late, half day, absent. Nobody marks a register
by hand. That is why raw punches are kept forever and verdicts are recomputed
rather than edited: the punch is the evidence, the verdict is only ever a
conclusion drawn from it.

This repository is the mobile client. The platform it mirrors — DRAIS LongTerm,
a Next.js application — is the source of truth for contracts and business
rules; see [docs/PARITY.md](docs/PARITY.md) for exactly what is inherited,
what deliberately differs, and the one piece of logic that is mobile-only.

---

## Running it

```bash
git clone https://github.com/xhenovolttechnologies/drais-mobile.git
cd drais-mobile
cp drais.env.example drais.env    # then fill in the database credentials
flutter pub get
flutter run
```

That is the whole setup: **one file to fill in**, then run. No server to start
first, no database to install, no build step to configure.

`drais.env` holds the TiDB Cloud credentials and is gitignored — this
repository is public, so it cannot travel with the source. Ask whoever
administers DRAIS for the values. Do not paste them into a chat, an issue, or
a pull request.

### Running without it

Skip the `cp` and the app starts in **API mode** instead, asking which DRAIS
server to connect to. Everything works; it just talks to a server rather than
to the database directly.

### How the mode is chosen

The app resolves its data source at startup, in this order:

1. `drais.env` beside the executable
2. `drais.env` in the working directory
3. `drais.env` in the platform application-support directory
4. `assets/drais.env` bundled into the build

If one is found, the app runs in **direct mode** — it connects straight to
TiDB Cloud in-process, with no server and no connect screen, the same way the
LongTerm desktop `.exe` does. If none is found, it falls back to **API mode**
and asks which DRAIS server to use.

The presence of the file is the entire switch. Delete it and the next launch
is back in server mode.

See [docs/DEPLOYMENT_MODES.md](docs/DEPLOYMENT_MODES.md) for the full picture.

## Building

```bash
tool/build.sh apk debug          # build/drais-<version>-debug.apk
tool/build.sh apk release        # build/drais-<version>-release.apk
tool/build.sh appbundle release  # build/drais-<version>-release.aab
```

Artefacts are named after the version and channel rather than the default
`app-debug.apk`, so the file sitting in someone's Downloads folder can be
identified. See [docs/VERSIONING.md](docs/VERSIONING.md).

## Versioning

```bash
dart run tool/bump_version.dart patch    # or minor / major / build / X.Y.Z
```

Updates `pubspec.yaml`, `lib/core/constants/app_version.dart` and
`CHANGELOG.md` together. `test/core/app_version_test.dart` fails the suite if
they drift or if the current version has no changelog entry.

## Tests

```bash
flutter test           # the app — 116 tests
cd server && dart test # the Dart backend — 18 tests
```

The suite runs without credentials; nothing in it touches the database.

## Layout

| Path | What lives there |
|---|---|
| `lib/app/` | Theme, routing, shell, module catalogue |
| `lib/core/` | Config, database, networking, errors, storage, logging, DI |
| `lib/features/` | Feature-first slices: `presentation → application → domain ← data` |
| `lib/shared/` | Widgets used across features |
| `server/` | A Dart backend (`shelf`), phase 1 of a strangler migration off Node |
| `docs/` | Architecture, parity, deployment modes, ADRs |
| `tool/` | Version bumping and artefact builds |

## Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — layers and dependency rules
- [PARITY.md](docs/PARITY.md) — what tracks LongTerm, what does not, and why
- [DEPLOYMENT_MODES.md](docs/DEPLOYMENT_MODES.md) — direct, server, and hosted
- [VERSIONING.md](docs/VERSIONING.md) — version rules, bumping, artefact naming
- [ROADMAP.md](docs/ROADMAP.md) — phases and what remains
- [docs/adr/](docs/adr/) — mobile architecture decisions
- [docs/platform/](docs/platform/) — inherited platform ADRs

## Known release blockers

- `applicationId` is still the Flutter template default `com.example.drais`.
- Release builds are signed with the **debug** keystore.
- The production credentials have been exposed in plain text elsewhere and are
  not yet rotated. They are not in this repository, but rotating them is still
  outstanding.
