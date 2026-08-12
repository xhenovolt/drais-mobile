# Inherited platform documentation

**These files are copies from DRAIS LongTerm. They are not mobile documents and must not be edited here.**

DRAIS Mobile is a client of the DRAIS platform, not a separate product. The decisions recorded in this folder constrain the mobile app exactly as they constrain the web app — they were made once, for the platform, and mobile inherits them.

They are copied rather than linked so that this repository is understandable when opened on its own, which was an explicit requirement: an engineer who has never seen the LongTerm repository should be able to work out why the mobile app authenticates with cookies, why it never opens a database connection, and why it does not implement grading rules.

## How to keep these current

The originals live at `DraisLongTermVersion/docs/`. When one changes there, re-copy it here and note the sync in `CHANGELOG.md`. **Edit the original, never the copy.** A divergent copy is worse than no copy: it silently answers the reader's question wrongly.

`lib/core/constants/app_version.dart` records `verifiedAgainstLongTerm`, the LongTerm version this client's contract expectations were last checked against. That constant and this folder should be refreshed together.

## What is here, and why it matters to mobile

| File | Origin | Why mobile needs it |
|---|---|---|
| `0008-two-auth-systems.md` | `docs/adr/` | The tenant-isolation model. Explains why the app derives nothing about scope locally, and why Control Center is permanently out of scope for mobile. |
| `0009-parent-portal-isolation-gate.md` | `docs/adr/` | The parent portal is a **different identity space**. A future parent app is a separate auth domain, not a role. |
| `0010-dual-database-mode.md` | `docs/adr/` | Why offline matters to Ugandan schools, and why real bidirectional sync is an unsolved design problem rather than an implementation gap. Directly informs `docs/OFFLINE_STRATEGY.md`. |
| `0011-platform-api-contract-freeze.md` | `docs/adr/` | The distinction between the frozen external API and the freely-changing internal one. Mobile consumes the **internal** API, so it must track LongTerm releases. |
| `0012-founder-independence.md` | `docs/adr/` | The project's operating philosophy. |
| `0013-swr-as-the-client-data-layer.md` | `docs/adr/` | The web client's caching and invalidation model, which the mobile cache deliberately mirrors in spirit. |
| `0014-client-rendered-app-router.md` | `docs/adr/` | Why the whole platform is client-rendered — the reason a mobile client is a natural fit rather than a rewrite. |
| `ADR_INDEX.md` | `docs/adr/README.md` | The full ADR index, including decisions not copied here. |
| `RBAC_ARCHITECTURE.md` | `docs/` | Permission codes, roles, wildcard semantics. `PermissionSet` mirrors this exactly. |
| `API_ERROR_HANDLING_GUIDE.md` | `docs/guides/` | The "zero silent failures" standard. `Failure` and `Result` are its mobile expression. |
| `ARCHITECTURE_REFERENCE.md` | `docs/architecture/` | The system map. |
| `TABLE_DICTIONARY.md` | `docs/database/` | Schema reference. Mobile never touches the database; this is here to explain what the API returns. |
| `PLATFORM_API.md`, `PLATFORM_CONTRACT_FREEZE.md` | `docs/` | The external API. **Mobile does not use it** — included so nobody mistakes the two surfaces. |
| `OFFLINE_MIGRATION_ASSESSMENT.md` | `docs/` | The platform's offline analysis, and the prior art any mobile offline work must start from. |
| `LONGTERM_CONTRIBUTING.md` | `CONTRIBUTING.md` | Backend conventions: versioning, commits, route rules, localization. Mobile's `CONTRIBUTING.md` follows the same shape. |

## What is deliberately not copied

LongTerm's `docs/` holds 203 files. Most are completion reports, forensic audits of specific data incidents, and superseded analyses — they document the history of subsystems mobile does not implement. Copying all of them would bury the dozen documents that actually bind this codebase.

The selection above is the set that constrains mobile work. The originals remain the complete record.
