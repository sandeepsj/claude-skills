# Verification Checklist — Vayu

Run through before marking work complete. Each failure aborts — fix, don't suppress.

## Universal Haskell checks

- [ ] Build passes with zero new warnings
- [ ] No `fromJust`, `head`, `tail`, `last`, `init`, `!!`, `read` introduced (`git diff` grep on added lines)
- [ ] No `undefined` or `error` in non-test code
- [ ] No `-fno-warn-incomplete-patterns` / `-Wno-incomplete-patterns` pragmas added
- [ ] All new `case` expressions on enum types are exhaustive (no lazy wildcards)
- [ ] No orphan instances
- [ ] No `OVERLAPPING` / `INCOHERENT` pragmas unless library-level justified
- [ ] `deriving` is explicit (`stock` / `newtype` / `anyclass`)
- [ ] `fourmolu --mode inplace $(git ls-files '*.hs')` has run
- [ ] `hlint src/` — suggestions addressed or consciously rejected
- [ ] New tests exist for new functions
- [ ] All tests pass, not just new ones
- [ ] No debug prints / commented-out code / dropped tests in the diff
- [ ] Imports are tidy; no unused

## Vayu-specific checks

### Codegen
- [ ] **Regenerated?** If any YAML changed (`doc/Api.yaml`, `doc/schemas/`, `doc/paths/`, `doc/DBQueries.yaml`, `doc/NetworkCalls.yaml`), ran `pnpm run generate:api:backend` and committed the generated output in the same commit
- [ ] **No hand edits** under `src/Vayu/Generated/`

### DB layer
- [ ] New DB table → registered in `src/Vayu/Types/Storage/BreezeDB.hs` (`BreezeDb` record + entity modification)
- [ ] `x-find` / `x-update` blocks use Haskell types (`Text`, `Int`, `Types.<EnumName>`), not `String`
- [ ] Nullable fields have `isMaybe: true`

### Enums
- [ ] Every enum schema has `x-enum: true`

### API layer
- [ ] New `operationId` is kebab-case
- [ ] Path referenced in `doc/Api.yaml` at the right position (specific before general)
- [ ] Handler in `Routes/Core.hs` with exact camelCase name matching operationId
- [ ] Handler parameter order matches Servant route: path captures → query → body → headers
- [ ] Handler delegates to Product, no business logic

### Network calls
- [ ] Request/response types in `doc/schemas/`
- [ ] Entry in `doc/schemas/external.yaml` with `x-schemas`
- [ ] Registered in `doc/NetworkCalls.yaml`
- [ ] Required config values (from `env:` fields) exist in `config.yaml`

### Layer discipline
- [ ] Product layer does NOT import `Vayu.Generated.Queries`, `Vayu.Generated.Types.Storage`, or `Vayu.Storage.Queries`
- [ ] Product functions use `withProductAPILogging` (API-facing) or `withFunctionLogging` (internal Flow helpers) — NOT scattered `logInfo`
- [ ] Pure helpers (no DB / HTTP / Redis / config / clock / throw) written in `LogM`, not `Flow`
- [ ] No legacy two-liner `logProductAPIRequest` + `logProductAPIResponse`
- [ ] Common ↔ Storage conversions use `fromGenType` / `toGenType` at the API boundary

### Commands
- [ ] Build: `pnpm build` (via `vayu-build` skill)
- [ ] Tests: `npx dotenv -- bash -c '$STACK_PATH exec vayu-hspec'` (via `vayu-test` skill)
- [ ] Format: `fourmolu --mode inplace $(git ls-files '*.hs')`
- [ ] Lint: `hlint src/`
- [ ] Rule-check the diff: `vayu-review` skill

## Code-review self-questions

- [ ] Would a teammate understand this diff without a walkthrough?
- [ ] For each new effectful function, thought about timeout / empty / retry / concurrent / schema-change failure modes?
- [ ] Does every `Maybe` in a record have a clear "when is this Nothing?" meaning?
- [ ] Any new abstractions with only one concrete use? (Delete them.)
- [ ] Any new helper that duplicates something in `Vayu.Utils.*`? (Check `plan/16-utils-reference.md`.)
