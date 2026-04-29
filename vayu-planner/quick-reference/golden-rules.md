# Golden Rules — Vayu Haskell

## Universal Haskell rules (never broken in any Haskell project)

### No runtime-crashing partials
- Never: `fromJust`, `head`, `tail`, `last`, `init`, `!!`, `read`
- Use: pattern match, `listToMaybe`, `lastMaybe`, `readMaybe`, `Data.Map.lookup`, `Data.Vector.!?`

### No stubs in shipped code
- Never: `undefined`, `error "TODO"`
- Use: `Either`, `Maybe`, `logAndThrowErr*`

### Exhaustive case matches
- No `-fno-warn-incomplete-patterns` / `-Wno-incomplete-patterns` pragmas
- No lazy `_ -> ...` wildcards on enums you own — list every constructor
- `case` on closed sum types must list all cases

### No orphan instances
- Instance for type `T` and class `C` belongs in the module of either `T` or `C`

### No overlapping / incoherent instances
- `OVERLAPPING`, `OVERLAPPABLE`, `INCOHERENT` pragmas are for library authors who've thought hard — not app code

### Side effects show up in types
- No `Text -> Text` that secretly hits the DB
- If you need IO, say so (`Flow a`, `MonadIO m`, explicit effect constraint)

### Strings
- `Text` for user-facing
- `ByteString` for bytes
- `String` only for tiny scripts and error messages

### Maps & folds
- `Data.Map.Strict`, `Data.HashMap.Strict` unless you have a reason for lazy
- `foldl'`, not `foldl` — `foldl` leaks thunks
- `null xs`, not `length xs == 0`

### Derive explicitly
- `deriving stock`, `deriving newtype`, `deriving anyclass` — pick one per derive
- `DerivingStrategies` pragma on

---

## Vayu-specific rules

### `no-edit-generated` *(error)*
Never edit files under `src/Vayu/Generated/`. Change the YAML spec (`doc/schemas/`, `doc/paths/`, `doc/DBQueries.yaml`, `doc/NetworkCalls.yaml`) and regenerate via `pnpm run generate:api:backend`.

### `product-uses-logger-wrappers` *(error)*
Functions that actually need Flow effects MUST use `withProductAPILogging` (for API handlers) or `withFunctionLogging` (for internal Flow helpers) from `Vayu.Product.Logger`. For helpers that do NOT need Flow effects, see `prefer-logm-for-pure-helpers` below. Do NOT add scattered `logInfo` calls, and do NOT use the legacy 2-line `logProductAPIRequest` / `logProductAPIResponse` pair.

### `prefer-logm-for-pure-helpers` *(warning — default for new helpers)*
If a function needs no DB, HTTP, Redis, config, request context, clock, or `throw`, write it in `Vayu.Utils.LogM` (NOT `Flow`). LogM is a pure writer-over-DList monad — no MonadIO, no MonadTrans, no MonadFlow — so the compiler enforces purity and tests use `runLogMPure` with zero Flow setup. Compose LogM helpers via `>>=`; lift to Flow exactly once at the boundary via `LogM.runLogM`. Primitive names mirror `Vayu.Services.Logger.Logger` (`logInfo`, `logFailure`, `logFunctionCalled`, `logFunctionCallResult`, `withFunctionCallLogging`, etc.). See the `pure-logm-helper` template and `plans/pure-logging/{00-overview,01-usage}.md`.

### `product-does-not-touch-generated-queries` *(error)*
Product layer must not import from `Vayu.Generated.Queries`, `Vayu.Generated.Types.Storage`, or `Vayu.Storage.Queries` directly. Go through `Services/Internal`. Redis is an exception — `Vayu.Storage.Redis` is generic cache access, import it freely.

### `prefer-operator-style` *(warning)*
Prefer `>>=`, `<&>`, `*>`, and helpers from `Vayu.Utils.Maybe` (`>>=?`, `>.`, `>$`) over `do` blocks for monadic chains of 1–2 steps. Reserve `do` for flows with 3+ reused bindings or nested case analysis.

### `register-new-table-in-BreezeDB` *(error)*
When adding a new DB table: YAML schema + `doc/DBQueries.yaml` + `doc/Api.yaml` registration is not enough. You MUST also register the entity in `src/Vayu/Types/Storage/BreezeDB.hs` (add to the `BreezeDb` record + entity modification). Forgetting this compiles but crashes at runtime.

### `common-vs-storage-conversion` *(warning)*
`Types.Common.X` (API) ↔ `Types.Storage.X` (DB) via `fromGenType` / `toGenType`. Always convert Storage → Common before returning from an API handler.

### `operationId-kebab-case` *(error)*
`operationId` in OpenAPI paths must be kebab-case (`create-my-feature`). Becomes camelCase in Haskell (`createMyFeature`). NOT PascalCase, NOT snake_case.

### `x-enum-required` *(error)*
Every enum schema must set `x-enum: true`. Without it, the generator emits a plain `Text` type instead of a Haskell enum with Beam/PostgreSQL instances.

```yaml
MyStatusEnum:
  type: string
  x-enum: true    # REQUIRED
  enum: [ACTIVE, INACTIVE]
```

### `check-utils-before-writing` *(warning)*
400+ utility functions already exist across `Vayu.Utils.*`. Check `plan/16-utils-reference.md` before writing a helper. Particular attention to:
- `Utils.Maybe` — operators + safe list ops (`>>=?`, `>>=??`, `?.`, `??.`, `>.`, `>$`, `maybeHead`)
- `Utils.Extra` — `lastMaybe`, country/province lookups, `generateNanoID`
- `Utils.DateTime` — 40+ date functions (`ist` timezone constant, arithmetic, formatting)
- `Utils.Aeson` — `encodeText`, `decodeText`, `safeFromJson`
- `Utils.Crypto` — HMAC, hashing
- `Utils.Breeze` — 225+ feature-flag extractors
- `Utils.Commons` — `returnFailure` for error responses
- `Utils.Either` — `>>=>`, `>>=>>` for `Either`-in-`Flow`

### Keep boundaries thin
- Translate domain errors → HTTP once, at the handler boundary
- Don't catch `SomeException` anywhere except process-top and request-handler-top
