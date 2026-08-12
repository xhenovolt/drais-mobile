# M0005: JSON serialisation is hand-written, not generated

- **Status:** Accepted
- **Date:** 2026-08-05
- **Affects:** `lib/features/*/data/dtos/`

## Problem

Flutter's default answer to JSON is `json_serializable` (often with `freezed`), driven by `build_runner`. It is the near-universal recommendation. Choosing against it needs a reason.

## Context

The DRAIS internal API is not uniform, and the inconsistencies are not hypothetical — they are in the two endpoints the foundation consumes:

- **`roles` has two different types.** `/api/auth/me` returns `[{id, name, slug, isSuperAdmin}]`. `/api/auth/login` returns `['Bursar', 'Class Teacher']`. Same field name, same subsystem, different type.
- **The payload sits under different keys.** Some routes return `{success, data}`, some `{success, message, data}`, and the auth routes return the user at a top-level `user` key with `setupComplete` as a sibling.
- **`isSuperAdmin` means different things.** Login computes it by matching role names against `'admin'`/`'super'`; `/api/auth/me` reads the `is_super_admin` column. The looser one would show a "Deputy Admin" a super-admin UI.
- **The subscription object is called `subscription` in one response and `subscriptionInfo` in another.**
- **MySQL/TiDB type coercion.** `BIGINT` can arrive as a string, `TINYINT(1)` as `0`/`1`.

A generated parser handles one shape and throws on the other. Every one of these needs a hand-written converter regardless — at which point the generator contributes a build step and hides the interesting logic behind an annotation.

## Decision

**DTO parsing is written by hand, in `data/dtos/`, with each accommodation commented and attributed to the backend behaviour that requires it.**

Rules:

1. **A missing required field throws** a `FormatException` naming the contract change. The API client converts it into a `MalformedResponseFailure` that says "this version of the app does not understand the response". Silently defaulting an absent `id` to `0` would surface the failure far from its cause.
2. **Optional fields get documented defaults**, with the reasoning inline where it is not obvious — for instance, an absent `hasAccess` defaults to `true`, because the request that returned the body evidently succeeded, and defaulting to `false` would lock out a working account over a missing field.
3. **Primitives are coerced, not cast** — `_int`, `_bool`, `_string`, `_dateTime` — because of the driver behaviour above.
4. **Every quirk cites its source.** A comment says *which route* returns the odd shape, so the next engineer can check whether it is still true.

## Alternatives considered

**`json_serializable`.** Rejected on the reasoning above: the shapes need custom converters anyway, and the build step is a permanent tax — `build_runner` in every checkout, every CI run, and every SDK upgrade, for a decade. It is also a common source of upgrade friction when the analyzer version moves.

**`freezed` for unions and immutability.** Attractive for `Result` and `Failure`. Rejected because Dart 3's sealed classes and pattern matching provide exhaustive switching natively — `Result` and `Failure` are sealed hierarchies with compile-time exhaustiveness and no generation at all. `freezed` would add a build step to duplicate a language feature.

**`dart_mappable`.** Same category, same objection.

**Generating clients from an OpenAPI spec.** The right long-term answer *if the spec existed*. LongTerm has no OpenAPI document, and [ADR-0011](../platform/0011-platform-api-contract-freeze.md) explains why the platform declined to generate one even for its frozen external API: a generated schema describes what the code currently does, which is not the same as what was promised. Writing a spec for ~685 internal routes to serve one client is not a trade worth making today.

## Trade-offs

- **More code per model, and it must be maintained by hand.** Real, and the main cost. It is bounded: only the fields the app uses are parsed.
- **A typo in a key is a runtime failure, not a compile error.** Mitigated by parsing being confined to `data/dtos/`, tested directly, and failing loudly with a message naming the contract.
- **This does not scale to fifty models without discipline.** Revisit if it becomes the bottleneck — the decision is reversible per feature, since nothing outside `data/` knows how parsing happens.

## Consequences

- No `build_runner`; `flutter pub get` and `flutter test` are the whole toolchain.
- Every backend quirk is visible, commented, and attributable — which is exactly the documentation a mobile engineer needs when a response looks wrong.
- The divergences found while writing these parsers became [PARITY](../PARITY.md), the record of what should eventually be fixed on the server.

## Future considerations

If LongTerm ever publishes an OpenAPI document for its internal API, generating clients from it becomes clearly correct and this decision should be revisited. The DTO layer is the only thing that would change.
