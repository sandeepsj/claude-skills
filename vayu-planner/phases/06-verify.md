# Phase 06 — Verify (Vayu)

**Goal:** before calling it done, run through Vayu's pre-commit mechanical checks. Each failure aborts the phase — fix, don't suppress.

## Checklist (in order)

1. **Regenerate** — if any YAML spec changed (`doc/Api.yaml`, `doc/schemas/*.yaml`, `doc/paths/*.yaml`, `doc/DBQueries.yaml`, `doc/NetworkCalls.yaml`), run:
   ```bash
   pnpm run generate:api:backend
   ```
   This runs all three pipelines. Commit the regenerated `src/Vayu/Generated/` files in the same commit as the spec changes. **Never commit half a regen.**

2. **Build** — the canonical command:
   ```bash
   pnpm build
   ```
   **Not** `stack build` directly. Zero errors and zero *new* warnings. Use the `vayu-build` skill to run and parse the output into a compact error list.

3. **Test** — full hspec suite:
   ```bash
   npx dotenv -- bash -c '$STACK_PATH exec vayu-hspec'
   ```
   Use the `vayu-test` skill. All green, not just the new ones.

4. **Format** — `fourmolu --mode inplace $(git ls-files '*.hs')`. Check the formatted output in; don't argue with the formatter.

5. **Lint** — `hlint src/`. Suggestions either applied or consciously rejected.

6. **Totality grep the diff** — scan for banned partials introduced by the change:
   ```bash
   git diff --cached | grep -E '\b(fromJust|head|tail|last|init|read|error|undefined)\b' | grep '^\+'
   ```
   Each hit in added lines is a defect. Replace with pattern match / `listToMaybe` / `readMaybe` / `fromMaybe` / proper error return.

7. **Warn-suppression grep** — scan for pragmas that silence the compiler:
   ```bash
   git grep -nE '(-fno-warn-incomplete|-Wno-incomplete)'
   ```
   If any of these appear in your diff, remove and fix the underlying non-exhaustive match.

## Vayu-specific mechanical checks

- **No edits under `src/Vayu/Generated/`** — ever. If the diff touches it, you either edited by hand (undo) or forgot to regen (run `pnpm run generate:api:backend`).
- **New DB table?** Confirm the same commit updates `src/Vayu/Types/Storage/BreezeDB.hs` (record + entity modification). Forgetting this compiles but crashes at runtime.
- **New enum schema?** Confirm `x-enum: true` is set. Without it the generator emits `Text`, not a proper Haskell enum.
- **New endpoint?** Confirm `operationId` is kebab-case (`create-my-feature` → `createMyFeature`) and referenced in `doc/Api.yaml`. Confirm the handler exists in `Routes/Core.hs` with the exact matching camelCase name.
- **New network call?** Confirm `doc/NetworkCalls.yaml` + `doc/schemas/external.yaml` updated; required config values exist in `config.yaml`.
- **Product layer diff** — confirm no imports from `Vayu.Generated.Queries`, `Vayu.Generated.Types.Storage`, or `Vayu.Storage.Queries`. If present, route through a Services/Internal module.
- **Logger usage in Product diff** — confirm `withProductAPILogging` / `withFunctionLogging` / `runLogM` wraps each new function. No scattered `Logger.logInfo` / `logProductAPIRequest` / `logProductAPIResponse`.

The `vayu-review` skill greps most of these automatically — run it on the staged diff.

## Fast-feedback loop during implementation

Don't wait until this phase for every build. Run `pnpm build` in a side terminal after each meaningful edit, and run the relevant `<X>Spec.hs` via `--match` frequently. The phase is the *final* gate, not the only one.

## What to output

- Command summary for each checklist item (pass / the one thing that needed a fix)
- Confirmation of Vayu-specific checks (regen, BreezeDB, x-enum, kebab-case, layer discipline)

## Next phase

`review` — final structural + failure-mode pass.
