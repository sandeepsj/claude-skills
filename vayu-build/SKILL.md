---
name: vayu-build
description: Compile the Vayu Haskell project with `pnpm build-fast` and return a structured error list. Use when the user says "build", "compile", "check for errors", "does this typecheck", "did my change break anything", or after making changes that might affect the build. Parses GHC output into `FILE:LINE:COL SEVERITY MESSAGE` lines for quick triage. Do NOT use `stack build` directly — `pnpm build-fast` is the canonical Vayu build.
allowed-tools: Bash, Read, Grep
---

# Vayu Build Skill

Runs `pnpm build-fast` in the Vayu project root and returns GHC errors/warnings in a compact form.

## How to invoke

```bash
pnpm build-fast
```

This runs `npx dotenv -- bash -c '$STACK_PATH build --fast -j10'` under the hood (defined in `package.json`). The `npx dotenv` wrapper loads `.env` (including `STACK_PATH=stack`) before invoking the build.

**Important**: The full vayu build takes 10-30 minutes. Use `--interleaved-output` or avoid piping through `tail` so progress is visible in real time.

## Workflow

1. Run `pnpm build-fast` via Bash.
2. If the build succeeds with `0 errors`, report success — the build passed.
3. Otherwise, for each error, read the relevant source file, understand the diagnostic, and suggest a fix.
4. If an error is about a missing Generated module / type, the answer is almost always **"regenerate"** — see the `vayu-codegen` skill. Run `pnpm run generate:api:backend` and retry the build.
5. If errors are about pattern match warnings, remember: **never** add `{-# OPTIONS -fno-warn-incomplete-patterns #-}`. Fix the underlying non-exhaustive match.

## Common error classes

| Error pattern | Likely cause | Remedy |
|---------------|--------------|--------|
| `Module 'Vayu.Generated.*' not found` | Stale codegen | `pnpm run generate:api:backend` |
| `Variable not in scope: <X>` from a Generated module | YAML spec ahead of regen | Regenerate |
| `Couldn't match type 'Text' with 'Maybe Text'` on a record field | YAML `required:` mismatch | Check the schema's `required` list |
| `No instance for (FromJSON ...)` on an enum | Missing `x-enum: true` | Add it and regenerate |
| `Variable fromJust not found` / linted partial | Banned partial function | Use pattern match / `listToMaybe` / `fromMaybe` |

## Related

- For *running tests*, see `vayu-test`.
- For *fixing codegen drift*, see `vayu-codegen`.
- For *reviewing a diff*, see `vayu-review`.
