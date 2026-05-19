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

**Important**: The full vayu build takes 10-30 minutes. A foreground `Bash` call buffers all output until exit, so you (Claude) would sit blind for 20+ minutes. Always run this build in the background and stream the log.

## Seeing progress in real time

Do **not** call `pnpm build-fast` as a normal foreground `Bash` — output won't appear until the build finishes.

Use this two-step pattern instead:

1. **Kick off the build in the background**, writing to a log file with line-buffering so `tee`/pipes don't hide progress:

   ```bash
   # stdbuf -oL keeps GHC's output line-buffered through the pipe
   stdbuf -oL pnpm build-fast > /tmp/vayu-build.log 2>&1
   ```

   Call this with `Bash` and `run_in_background: true`. You get a shell id back immediately.

2. **Stream the log with `Monitor`** so each new line shows up as it's written:

   ```bash
   tail -n +1 -F /tmp/vayu-build.log
   ```

   Run this via `Monitor` (not `Bash`). Every stdout line becomes a notification, so build progress (module-by-module compile lines, GHC errors as they appear) is visible live without polling. When the background build finishes you'll be auto-notified — then stop the Monitor.

   Alternatively, if `Monitor` can target a background shell directly by id, point it at the build shell instead of `tail -F`.

**Why not just `tee`?** The existing `scripts/run-build.sh` does `pnpm build 2>&1 | tee`. That's fine for capturing the full log, but `tee` and many GHC stages block-buffer when stdout isn't a TTY, so even a foreground call hides progress for minutes at a time. The `stdbuf -oL` + background + `Monitor` combo is what actually gives you a live feed.

**Do not** try to `sleep` and re-read the log — you'll burn cache and miss lines. `Monitor` is the right tool here.

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
