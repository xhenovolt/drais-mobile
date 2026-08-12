# Coding standards

These mirror DRAIS LongTerm's conventions where a Dart equivalent exists, and state the mobile-specific rules where it does not.

`flutter analyze` must be clean before every push. It is configured strictly in `analysis_options.yaml`: strict casts, strict inference, strict raw types, and `unawaited_futures` promoted to an **error** — a silently dropped future is the mobile equivalent of an unawaited database write.

## Non-negotiables

These are the rules a review must reject a change over.

1. **All HTTP goes through `ApiClient`.** No feature constructs a `Dio`. This mirrors `apiClient.ts`: *"ALL client-side API calls MUST go through apiFetch. Direct fetch() is forbidden."*
2. **Repositories return `Result<T>` and never throw.** A caller cannot forget a failure case, because the compiler rejects an incomplete `switch`.
3. **No business logic in the client** ([M0004](adr/M0004-no-business-logic-in-the-client.md)). The reviewer's question is: *where did this number come from?*
4. **Never send `school_id`.** The server derives it from the session and ignores client input ([ADR-0008](platform/0008-two-auth-systems.md)).
5. **Permission checks decide what to draw, never what is allowed.**
6. **No `print`.** Use `AppLogger`; the lint enforces it.
7. **Never log a credential.** `Redaction` runs unconditionally, but do not rely on it — think before adding a value to a log context.
8. **Nothing credential-shaped in `SharedPreferences`.** `SecureStore` or nowhere.
9. **Paginate every list endpoint.** Directly inherited from `CONTRIBUTING.md`.
10. **Clear the cache on sign-out.** Cached tenant data outliving a session is a device-side isolation failure.

## Layering

Dependencies point inward: `presentation → application → domain ← data`.

- `domain/` imports nothing from other layers. No `dio`, no `flutter`, no JSON.
- `data/` may import `domain/` and `core/`.
- `application/` imports `domain/` only — never a DTO, never a data source.
- `presentation/` imports `application/` and `domain/`.
- A `DioException` never escapes `core/network/`.

If a file needs an import that breaks this, the design is wrong, not the rule.

## Naming

| Thing | Convention | Example |
|---|---|---|
| Files | `snake_case.dart` | `auth_repository_impl.dart` |
| Classes | `UpperCamelCase` | `AuthController` |
| Members | `lowerCamelCase` | `restoreSession` |
| Private | leading underscore | `_loadIdentity` |
| Constants | `lowerCamelCase` in an `abstract final class` | `ApiEndpoints.login` |
| Providers | `<thing>Provider` | `authControllerProvider` |
| DTOs | `<Entity>Dto` | `AuthUserDto` |
| Failures | `<Kind>Failure` | `AuthorizationFailure` |

**Mirror the backend's names.** `ApiEndpoints.login` is `/api/auth/login`. `ApiErrorCode.sessionExpired` is `SESSION_EXPIRED`. A renamed concept is a concept two engineers will fail to connect.

## Comments

The house style in both repositories is the same: **comments explain why, never what.**

The LongTerm ADRs are the model — they record what was traded away and what the alternative would have cost. Apply the same standard in code:

```dart
// Good — explains a decision that will look wrong later.
// Local state is cleared unconditionally. A user who taps "sign out" is
// signed out; a failed network call must never leave a live session cookie
// on the device.

// Bad — restates the code.
// Clear the local state.
```

Document every public API member — `package_api_docs` is enabled. Where a member exists because of a backend quirk, **cite the route**: `// /api/auth/login returns roles as bare strings.`

## Immutability

State classes are immutable with `copyWith`. Entities are immutable. Prefer `final` locals (the lint enforces it). Never mutate a list held in state — build a new one.

## Error handling

Every failure is a subtype of `Failure`, carrying two audiences at once: `message` for the user and `technicalDetail` for the log. Never show `technicalDetail` in production UI, and never put a raw exception string in `message`.

When adding a `Failure` subtype, add it to `ErrorView._titleFor` and `_iconFor` — both switches are exhaustive, so the compiler will tell you.

## Testing

Test the seams:

- **DTO parsing** — every backend shape quirk deserves a case.
- **Permission semantics** — these must match the server exactly.
- **Error classification** — code and status mapping.
- **Redaction** — it is a security control, tested like one.
- **Configuration validation** — the failure cases matter more than the happy path.

Test names read as sentences: `'a wrong password does NOT invalidate a session'`. When a test pins client behaviour to a server behaviour, say so in a comment — the next engineer needs to know it is not arbitrary.

## Localisation

LongTerm requires every user-facing string in **both English and Arabic**, with the dictionaries in `src/locales/{en,ar}.json`.

Mobile strings are currently English-only in source, which is a **known gap** recorded in [ROADMAP](ROADMAP.md). Until `flutter_localizations` lands: keep user-facing strings short, plain, and in one place per screen so extraction is mechanical, and never concatenate sentence fragments — they do not survive translation, and they break under RTL.

## Dependencies

Adding a package needs a reason in the PR. The bar: *would writing this ourselves be worse than maintaining this dependency for ten years?*

`meta` is declared explicitly because it is imported directly, even though it arrives transitively. Code-generation dependencies need an ADR — [M0005](adr/M0005-hand-written-serialization.md) explains why the default answer is no.

## Before you push

```bash
flutter analyze && flutter test
```

Then check the docs still describe what the code does. In-code documentation beats `docs/` for behaviour — it is closer to the code and more likely to stay true. `docs/` is for decisions.
