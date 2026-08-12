# Flutter-first architecture: assessment

**Status:** Analysis. No implementation performed beyond removing the embedded-Node experiment.
**Date:** 2026-08-05 · **Assessed against:** DRAIS Mobile 1.0.0, DRAIS LongTerm 1.173.15

---

## 0. Headline

**The target architecture is already the current architecture.** DRAIS Mobile is a native Flutter client with no JavaScript runtime, no embedded server, and no database driver. The embedded-Node experiment has been removed; nothing depended on it.

Four gaps separate today from the stated goal, and only the first is a correctness issue:

| # | Gap | Severity |
|---|---|---|
| 1 | `AppConfig` has a **compile-time default** of `http://10.0.2.2:3000` | Must fix |
| 2 | No offline persistence layer — cache is `SharedPreferences` JSON | Must build |
| 3 | Typed clients exist for `/api/auth/*` only; 691 routes total | Incremental |
| 4 | User-facing strings are English-only; platform requires en + ar | Compliance gap |

## 1. On the word "full-stack"

Your own clarification is correct and I'll adopt it as the definition for this document:

> The goal should be eliminating the Node.js runtime **on the client**, not eliminating the server itself.

Under that definition DRAIS Mobile is a **native Flutter client of a remote DRAIS server**, and "Flutter-first" means Flutter is the application platform for mobile users — owning state, navigation, persistence, offline behaviour and device integration — while the server owns data, business rules and authorization.

The stricter reading (backend rewritten in Dart) is costed in §4 and is not recommended.

## 2. Current state — verified, not asserted

### 2.1 Runtime dependencies of the APK

Complete dependency list:

```
flutter · cupertino_icons · flutter_riverpod · go_router · dio
flutter_secure_storage · shared_preferences · connectivity_plus
package_info_plus · meta
```

Nine packages. **None** is a JavaScript runtime, an embedded server, or a database driver.

```
$ grep -rn "^import" lib/ | grep -v "package:drais|flutter|dio|go_router|
    shared_preferences|connectivity|meta|dart:"
(no results)
```

The only occurrences of "MySQL" in the codebase are comments explaining what must never be added.

**The APK cannot fail because Node is absent, npm packages are missing, or a JavaScript process crashed** — there is no JavaScript in it. Build toolchain is `flutter pub get` and `flutter build`; there is no `build_runner` step either ([M0005](adr/M0005-hand-written-serialization.md)).

### 2.2 The base-URL abstraction

Already present and already the only knob:

```dart
apiBaseUrl: _normaliseBaseUrl(String.fromEnvironment('DRAIS_API_BASE_URL', ...))
String resolve(String path) => path.startsWith('http') ? path : '$apiBaseUrl$path';
```

Endpoint constants are origin-relative (`/api/auth/login`, `/api/attendance`), so the server address appears in exactly one place. Switching environments is one build flag ([ENVIRONMENTS](ENVIRONMENTS.md)).

### 2.3 Localhost audit — one real finding

| Location | Verdict |
|---|---|
| `app_config.dart:52` — `defaultValue: 'http://10.0.2.2:3000'` | **Violation.** A build with no `--dart-define` silently targets a developer's machine. |
| `env/development.json` | Acceptable — developer convenience, never in a release build |
| `app_config.dart:122` — `AppConfig.test` | Acceptable — test fixture only |
| `app_config.dart:213–215` — `localhost`/`127.0.0.1`/`10.0.2.2` list | **This is the guard, not the violation.** `validate()` refuses to start a production build pointed at these. |

**Recommended fix:** remove the default entirely. Absent `DRAIS_API_BASE_URL` becomes a validation failure in every environment, so a build must state its target. Two-line change; deferred pending approval per your instruction not to implement.

## 3. Remaining Node.js / Next.js dependencies

**In the shipped application: none.**

**In the development workflow: one, and it is not a runtime dependency.** Developing against a local backend means running `npm run dev` in the LongTerm repository — the same as any client developed against any server. The APK does not care; point it at staging and no Node exists anywhere in the loop.

**In production: the server is Next.js.** That is a property of the backend, not a dependency of the client. The client speaks HTTP and would be unchanged if the server were rewritten in Go tomorrow.

## 4. What could be rewritten in Dart — and what that would cost

Measured in DRAIS LongTerm 1.173.15:

```
691   API routes
61,433   LOC   src/lib (business logic)
316,308  LOC   src total
```

The engines:

| Subsystem | LOC | Notes |
|---|---|---|
| `drce` | 9,002 | Report card engine — canvas layout, bilingual rendering |
| `attendance` | 8,152 | Device time policies, drift, hybrid marking |
| `biometric` | 5,018 | ZKTeco integration, identity hardening |
| `snapshots` | 4,099 | Immutable report snapshots ([ADR-0005](platform/ADR_INDEX.md)) |
| `ingestion` | 3,375 | Bulk import |
| `finance` | 1,536 | Fee rules, receipts |
| `rbac` | 897 | Permission catalog, wildcard expansion |

A Dart backend means reimplementing ~61k lines of rule-bearing logic against the same 255-table schema, then running two implementations in parallel until trusted. Each has ADRs recording non-obvious decisions made under real-world pressure — the sort of knowledge that does not survive a port.

**Not recommended.** The failure mode is not "it takes long"; it is that two systems end up disagreeing about a child's grade or a school's balance, and neither can be corrected without breaking the other ([M0004](adr/M0004-no-business-logic-in-the-client.md)).

## 5. Client-side responsibilities — the correct split

Your list, assessed. Most of it is unambiguously client work.

### 5.1 Belongs in Dart (build these)

| Capability | Status | Notes |
|---|---|---|
| State management | **Done** | Riverpod ([M0001](adr/M0001-riverpod-as-state-and-di.md)) |
| Caching | Partial | Works; needs a real database — §6 |
| Encryption at rest | **Done** | Keystore-backed via `SecureStore` |
| Input validation (shape) | **Done** | Client pre-check; server independently repeats |
| Retry, backoff, timeouts | **Done** | `RetryInterceptor` |
| Connectivity handling | **Done** | `NetworkInfo` |
| Local permission checks | **Done** | `PermissionSet` — mirrors server semantics, for rendering |
| Offline queue / outbox | **Not built** | Blocked on server idempotency — §7 |
| Sync scheduling | **Not built** | Backoff, batching, foreground/background policy |
| Biometric unlock | **Not built** | Device-local app unlock (`local_auth`) — distinct from ZKTeco enrolment, which is server work |
| Formatting / localisation | **Not built** | en + ar with RTL |

### 5.2 The one item needing a distinction: "attendance calculations offline"

Split it in two:

- **Capture — Dart, safe.** "Teacher T marked learner L present at 07:42 local, device clock offset X, on 2026-08-05." A record of what a person did. Store it, show it as pending, replay it.
- **Derivation — server.** Whether that becomes *present* or *late*; whether the day is a school day; how device clock drift is reconciled. Four ADRs govern this ([ADR-0001](platform/ADR_INDEX.md) raw events, [0002](platform/ADR_INDEX.md) device wall-time, [0003](platform/ADR_INDEX.md) time policies, [0004](platform/ADR_INDEX.md) timezone-safe dates), it is per-school configurable, and it is 8,152 lines.

Capturing offline gives you the entire user-visible benefit. Deriving offline gives a device an opinion that will eventually contradict the server's — on attendance records, which are the platform's most contested data.

**Recommendation:** offline capture, server derivation. The UI shows "11 marks pending sync", not a provisional attendance rate.

## 6. Local persistence — recommendation

| Option | Verdict |
|---|---|
| **Drift** (SQLite) | **Recommended** |
| Isar | Fast, but v3 maintenance has been uncertain — poor bet for a decade |
| Hive | Fine for key-value; no queries, no migrations, weak for relational data |
| `sqflite` raw | Drift without the type safety |
| `SharedPreferences` (today) | Plaintext, no queries, not built for volume |

**Drift**, because:

- **SQL, matching the platform's model.** Engineers already reason in SQL here; the mental model transfers.
- **Real migrations with schema versioning.** An offline database outlives app versions; a store without migrations means wiping user data on upgrade — unacceptable once it holds unsent marks.
- **Typed queries checked at compile time**, so a schema change breaks the build rather than a phone in a school.
- **Relational data** — learners, classes, attendance, sync queue — with joins.
- **Maturity.** Actively maintained, large user base, an unexciting choice that will still be here in ten years.

Note this contradicts [M0005](adr/M0005-hand-written-serialization.md)'s no-codegen stance: Drift uses `build_runner`. That is a deliberate, narrow exception — schema-migration safety is worth a build step in a way that JSON parsing was not. It needs its own ADR.

**Encryption:** SQLCipher via `sqlcipher_flutter_libs`, key in the keystore. The database will hold learner data.

**Non-negotiable:** cleared on sign-out. Cached tenant data outliving a session on a shared school tablet is a device-side isolation failure even when the server behaved correctly.

## 7. The blocker: server-side idempotency

**Offline writes cannot be built safely until the internal API supports idempotency keys.**

Without them, replaying a queued write after reconnection can double it — a duplicated attendance record, a duplicated payment, a guardian SMS sent twice and billed twice. This is why `RetryInterceptor` never retries `POST`/`PUT`/`PATCH`/`DELETE` today.

Only the external Platform API has this mechanism ([ADR-0011](platform/0011-platform-api-contract-freeze.md)). Its implementation is the model: client sends `Idempotency-Key`, server stores it with the result, replay returns the original outcome.

**This is a server change and it gates Phase 3.** It is small — a table and a middleware — but nothing offline is safe before it.

## 8. Migration roadmap: Next.js frontend → Flutter-first

**Recommendation: Flutter-first for mobile workflows, not Flutter-only for the platform.**

The web UI should be retained for what it is genuinely better at, and a phone is genuinely worse at:

| Keep on web | Why |
|---|---|
| School setup and configuration | Long forms, done once, by an administrator at a desk |
| Bulk import / ingestion (3,375 LOC) | File handling, error review at scale |
| Report card design (DRCE) | Canvas layout — needs a large screen |
| Printing, PDF export | Print pipeline, paper |
| Control Center | Separate auth domain, permanently out of mobile scope ([ADR-0008](platform/0008-two-auth-systems.md)) |
| Finance reconciliation | Spreadsheet-shaped work |

| Move to Flutter | Why |
|---|---|
| Attendance marking | Time-critical, done standing up, in a classroom |
| Learner lookup | Constant, mobile-shaped |
| Notifications | Push is a capability the web does not have |
| Fee balance enquiry (read) | Quick lookup at a counter |
| Timetable | Read-mostly, ideal offline |
| Approvals | Short interactions, away from a desk |

Retiring the web frontend would mean rebuilding 316k lines of UI for workflows that are worse on a phone. **Two clients, one platform** is the correct end state.

## 9. Risks and trade-offs

| Risk | Severity | Mitigation |
|---|---|---|
| **No contract tests upstream.** LongTerm has no coverage of routes, RBAC or auth. A backend change breaks the client silently. | **High** | Contract tests on consumed routes; `verifiedAgainstLongTerm`; a minimum-client-version response |
| **Offline writes without idempotency duplicate data** | **High** | Do not build Phase 3 until §7 lands |
| **Deployed APKs cannot be updated quickly.** A school on a six-month-old build meets a changed internal API. | Medium | Minimum-version gate; the client already fails with an honest "please update" message |
| **Business logic creeping into Dart** for offline convenience | Medium | [M0004](adr/M0004-no-business-logic-in-the-client.md); review question: *where did this number come from?* |
| **Offline DB holds learner data on a lost phone** | Medium | SQLCipher + keystore; clear on sign-out; consider a retention window |
| **`build_runner` enters the toolchain** via Drift | Low | Confined to persistence; documented exception |
| **TiDB connection pressure** as mobile traffic grows | Low | Server-side concern; measure before large rollout |
| **Two clients drift in behaviour** | Medium | Server owns rules, so they cannot disagree on *data* — only on presentation |

## 10. Phased implementation plan

Each phase is independently shippable and leaves the app working.

### Phase 0 — Close the localhost gap *(hours)*
Remove the compile-time base-URL default; absent `DRAIS_API_BASE_URL` fails validation everywhere. Add a release-build assertion. **No dependencies. Do this first.**

### Phase 1 — Prove the contract *(days)*
Run the client against a live DRAIS server. Verify login, session restore, expiry, permission loading, error mapping. Correct any DTO assumption derived from reading TypeScript rather than observing traffic. **This is the highest-value unvalidated step in the project.**

### Phase 2 — First module: Attendance, online-only *(2–3 weeks)*
Typed client, DTOs, repository, controller, screens. Establishes the module pattern ([ROADMAP](ROADMAP.md)). Ships user value immediately.

### Phase 3a — Persistence layer *(1–2 weeks)*
Drift + SQLCipher. Migrate the read cache off `SharedPreferences`. Read-only offline: timetable, class lists, learner profiles, with "last updated" shown. Write the ADR for the codegen exception.

### Phase 3b — Server idempotency *(platform work, parallel)*
`Idempotency-Key` on internal write routes. **Gates Phase 4.**

### Phase 4 — Offline capture and sync *(3–4 weeks, after 3a + 3b)*
Outbox of intents, sync scheduler with backoff, pending-state UI, conflict surfacing. Attendance first.

### Phase 5 — Platform hardening *(parallel, ongoing)*
Contract tests; minimum-version gate; device-token endpoint for push; localisation (en + ar, RTL); CI running `flutter analyze && flutter test`.

### Phase 6 — Module expansion
Students → Notifications → Finance (read) → Timetable, per [ROADMAP](ROADMAP.md).

**Critical path:** Phase 0 → 1 → 2 → 3a → (3b) → 4.

## 11. Decisions requested

1. **Approve Phase 0** — remove the localhost default. *(Recommend: yes, immediately.)*
2. **Confirm the attendance split** — offline capture, server derivation (§5.2). *(Recommend: yes.)*
3. **Approve Drift** and the narrow codegen exception (§6). *(Recommend: yes.)*
4. **Sponsor the server idempotency work** (§7). *(Recommend: yes — it gates all offline writes.)*
5. **Confirm two-client end state** (§8) rather than retiring the web frontend. *(Recommend: yes.)*

No implementation will proceed until these are settled.
