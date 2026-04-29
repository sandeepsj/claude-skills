---
name: vayu-codegen
description: Walk through adding a new API endpoint, DB table, or network call in the Vayu repo — the YAML edits (doc/schemas, doc/paths, doc/Api.yaml, doc/DBQueries.yaml, doc/NetworkCalls.yaml), the regeneration command, and the post-regen manual wiring (Core.hs handler, BreezeDB registration). Use when the user says "add endpoint", "new DB table", "new network call", "add x-find query", "register new operationId", or anything involving Vayu's YAML-driven code generation.
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
---

# Vayu Codegen Skill

Vayu generates a lot of Haskell from YAML specs. This skill covers the three codegen pipelines and the human-edited seams around them.

## The three pipelines

| Pipeline | Input spec | Regen command | Output |
|----------|------------|---------------|--------|
| Types + API | `doc/Api.yaml` (with `doc/schemas/`, `doc/paths/`) | `pnpm run generate:api:backend` | `src/Vayu/Generated/Types/Common/*`, `src/Vayu/Generated/Types/Storage/*`, `src/Vayu/Generated/API.hs`, `src/Vayu/Generated/Accessor.hs` |
| DB Queries | `doc/DBQueries.yaml` | `pnpm run generate:db:backend` | `src/Vayu/Generated/Queries/*.hs` |
| Network Calls | `doc/NetworkCalls.yaml` (with `doc/schemas/external.yaml`) | `pnpm run generate:network:backend` | `src/Vayu/Generated/NetworkCalls/*.hs` |

`pnpm run generate:api:backend` runs all three. **Never edit files under `src/Vayu/Generated/` manually.**

---

## Workflow A — New API endpoint

1. **Define the request / response schemas** in `doc/schemas/`. Add `x-enum: true` on any enum schema. Reserved words: `_type` in YAML → `__type` in Haskell (double underscore).
2. **Define the path** in `doc/paths/`. The `operationId` **must be kebab-case** (`create-my-feature` → `createMyFeature` in Haskell). NOT PascalCase, NOT snake_case.
3. **Reference the path** in `doc/Api.yaml` — position matters for route ordering (Servant tries top-down; more specific routes before more general ones).
4. **Regenerate:** `pnpm run generate:api:backend`.
5. **Implement the handler** in `src/Vayu/Routes/Core.hs` with the exact name matching the camelCase operationId. Parameter order must match the Servant route: path captures → query params → request body → headers (in declaration order). All headers are `Maybe Text` even if required.
6. **Delegate to Product** — the handler should just extract headers, call `Vayu.Product.<Domain>.<Feature>.<fn>`, return. No business logic in the handler.

See the `servant-core-handler` template (in vayu-planner) for handler shape.

## Workflow B — New DB table

1. **Define the schema** in `doc/schemas/` with `x-find` / `x-update` blocks.
   - `typename` must be a Haskell type: `Text`, `Bool`, `Int`, `Scientific`, `Types.<EnumName>` — **never `String`**.
   - `isMaybe: true` is **required** for nullable fields (not in `required:` list); otherwise type mismatch.
   - `isArray: true` generates `IN (...)`; pair with `returnsArray: true`.
2. **Add to `doc/DBQueries.yaml`** — the query helpers.
3. **Add to `doc/Api.yaml`** `components/schemas` — so Common/Storage types emit.
4. **Register in `src/Vayu/Types/Storage/BreezeDB.hs`** (manual, critical):
   - Add the table entity to the `BreezeDb` record.
   - Add the entity modification (field name mappings, etc.).
   - **Forgetting this step compiles but crashes at runtime** — the table isn't in the schema the DB runtime knows about.
5. **Regenerate:** `pnpm run generate:api:backend`.

## Workflow C — New network call (outbound HTTP)

1. **Define request / response types** in `doc/schemas/` (or `doc/schemas/external.yaml` for external-only types).
2. **Add to `doc/schemas/external.yaml`** with `x-schemas` — declares the external service binding.
3. **Register in `doc/NetworkCalls.yaml`** — the call spec (method, URL template, env var config keys).
4. **Regenerate:** `pnpm run generate:network:backend` (or the main `generate:api:backend`).
5. **Ensure config values exist** — any `env:` fields must have real values in `config.yaml` and runtime config, otherwise the call fails at first invocation.

## YAML type-mapping crib sheet

| OpenAPI | Haskell |
|---------|---------|
| `type: string` | `Text` |
| `type: integer` | `Int` |
| `type: number` / `format: double` | `Scientific` |
| `type: boolean` | `Bool` |
| `type: string, format: date-time` | `LocalTime` |
| `type: string, format: date` | `UTCTime` |
| `type: object` (freeform) | `Value` (Aeson) |
| `type: array, items: X` | `[X]` |
| In `required:` list | `T` |
| NOT in `required:` list | `Maybe T` |

## Common gotchas

- **Missing `x-enum: true`** on an enum schema → generator emits `Text`, not a Haskell enum. No Beam/PostgreSQL instances.
- **operationId not kebab-case** → generator either errors or produces a mangled Haskell name that doesn't match handler expectations.
- **Handler name drift** → if `Core.hs` handler doesn't exactly match camelCase operationId, `Generated/API.hs` won't compile.
- **Forgot BreezeDB registration** → compiles; dies at first query.
- **Position in `doc/Api.yaml`** → two paths that could both match the same URL: the earlier one wins. Put specific routes before catch-alls.

## After regeneration — verify

Use the `vayu-build` skill to compile and surface any errors. Then use `vayu-test` to run the suite. Don't commit partial regen (e.g., updated spec but stale generated files) — CI will fail for everyone else.
