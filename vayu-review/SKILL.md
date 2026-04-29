---
name: vayu-review
description: Review a Vayu diff (staged changes, a branch, or a specific file set) for Vayu golden-rule violations — banned partial functions, incomplete-pattern pragmas, Product layer importing Generated queries, scattered logInfo calls instead of the logger wrappers, LogM-vs-Flow misuse, missing BreezeDB registration, stale codegen, non-kebab-case operationIds, missing x-enum. Use when the user says "review my changes", "check my diff", "pre-PR review", "scan for violations", or before marking work complete.
allowed-tools: Bash, Read, Grep, Glob
---

# Vayu Review Skill

Greps a code change for Vayu's specific anti-patterns. Not a substitute for reading the diff — this is the mechanical pass you run before the human pass.

## How to invoke

```bash
./scripts/review-diff.sh                 # staged changes vs HEAD
./scripts/review-diff.sh --branch beta   # current branch vs 'beta'
./scripts/review-diff.sh --files src/Vayu/Product/Cart/X.hs src/Vayu/Product/Cart/Y.hs
```

The script prints a section per rule, listing every violation with file:line. Exit code is non-zero if any `error` severity rule fires.

## Rules it checks

### Errors (must fix)

| Rule | Check |
|------|-------|
| `no-edit-generated` | Any diff touching `src/Vayu/Generated/` |
| `no-partial-functions` | `fromJust`, `\bhead\b`, `\btail\b`, `\blast\b`, `\binit\b`, `\bread\b`, `!!`, `\berror\b`, `\bundefined\b` in added lines |
| `no-warn-suppression` | `-fno-warn-incomplete-patterns`, `-Wno-incomplete-patterns`, `-fno-warn-incomplete-uni-patterns` anywhere in diff |
| `product-does-not-touch-generated-queries` | Lines matching `^import.*Vayu\.Generated\.Queries\|^import.*Vayu\.Generated\.Types\.Storage\|^import.*Vayu\.Storage\.Queries` in files under `src/Vayu/Product/` |
| `product-uses-logger-wrappers` | Functions in Product layer that use `Flow` and don't call `withProductAPILogging` / `withFunctionLogging` / `runLogM` — manual review flagged |
| `operationId-kebab-case` | `operationId:` values in YAML diffs that aren't kebab-case |
| `x-enum-required` | Enum schemas in `doc/schemas/` without `x-enum: true` |
| `register-new-table-in-BreezeDB` | New entry in `doc/DBQueries.yaml` without a matching `src/Vayu/Types/Storage/BreezeDB.hs` edit in the same diff |

### Warnings (consider)

| Rule | Check |
|------|-------|
| `prefer-logm-for-pure-helpers` | New function in `Flow` with no DB / HTTP / Redis / config calls — candidate for `LogM` |
| `prefer-operator-style` | `do` block with exactly 1 or 2 `<-` bindings — candidate for operator style |
| `scattered-logInfo` | `Logger.logInfo` inside Product layer (should be in a wrapper, not ad-hoc) |
| `common-vs-storage-conversion` | `Types.Storage.X` returned from a Product function (should convert via `fromGenType`) |
| `check-utils-before-writing` | New helper function name that matches an existing `Vayu.Utils.*` export |

## Workflow

1. Run `./scripts/review-diff.sh` (choose scope: `--staged`, `--branch <base>`, or `--files ...`).
2. For each `error` severity violation: show the offending lines, explain the rule, suggest the fix.
3. For each `warning`: mention it, but defer to human judgement — these are heuristics.
4. If the diff touches `doc/schemas/` / `doc/DBQueries.yaml` / `doc/paths/` / `doc/Api.yaml` / `doc/NetworkCalls.yaml` → remind user to run `pnpm run generate:api:backend` and confirm the generated output was updated in the same commit.
5. Hand off to `vayu-build` after fixes to confirm the code still compiles.

## When this skill doesn't apply

- Diffs confined to `doc/` or config — run it anyway; some rules (operationId, x-enum) are YAML-only.
- Style-only changes — this skill doesn't do formatting. Use `fourmolu` directly.
- PR narrative / design review — that's a human task; this skill only catches mechanical violations.

## Related

- `vayu-planner` phase 7 (review) — the human review lens this skill complements.
- `vayu-build` / `vayu-test` — run after fixes.
