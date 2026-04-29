---
name: vayu-test
description: Run the Vayu hspec test suite with the canonical command `npx dotenv -- bash -c '$STACK_PATH exec vayu-hspec'` and summarise failures. Use when the user says "run tests", "test this", "hspec", "run the suite", "did I break anything", or after a change that affects existing functionality. Do NOT use `stack test` — it misses env var loading and diverges from CI.
allowed-tools: Bash, Read, Grep
---

# Vayu Test Skill

Runs the Vayu hspec test binary via the canonical `dotenv + stack exec` incantation.

## How to invoke

```bash
./scripts/run-tests.sh                  # full suite
./scripts/run-tests.sh --match "Cart"   # filter by spec description
./scripts/run-tests.sh --failed         # rerun only previously-failed
```

The script:
1. `cd`s to the Vayu repo root.
2. Runs `npx dotenv -- bash -c '$STACK_PATH exec vayu-hspec' -- <args>`.
3. Streams output to `/tmp/vayu-test.log`.
4. Parses hspec output: failed spec descriptions + file:line of each failure + the expectation vs. got diff when present.
5. Prints a summary: `X examples, Y failures, Z pending`.

## Workflow

1. Run `./scripts/run-tests.sh` (or with `--match`/`--failed` to narrow).
2. If all pass: report success with example count.
3. Otherwise, for each failure:
   - Read the spec file at the reported line.
   - Read the module under test.
   - Form a hypothesis. Run with `--match "<specific describe text>"` to iterate quickly without the whole suite.
4. For LogM-based helpers, use `runLogMPure` in tests — no Flow runtime, no container. See the `pure-logm-helper` template in `vayu-planner`.
5. For integration tests that hit a real DB / HTTP, the CATS infrastructure is likely involved — see the `plans/cats/reference_cats_testing.md` doc.

## Why the dotenv wrapper?

The `vayu-hspec` binary reads env vars for DB URLs, external service endpoints, feature flags. `.env.test` (loaded by `npx dotenv`) supplies them. `stack test` bypasses dotenv → tests that depended on env look like they pass or fail for mysterious reasons. **Always go through the wrapper.**

## Common failure classes

| Symptom | Likely cause | Next step |
|---------|--------------|-----------|
| "No such tests match" | Typo in `--match`, or hspec description changed | Run without `--match` first to list examples |
| Every integration test fails with connection error | DB/Redis not running | Start containers per `CATS` setup docs |
| Pattern-match warning → test failure at runtime | Non-exhaustive `case` on enum | Fix the match; exhaustive-case template in vayu-planner |
| Timeout | Fork not cleaned up; async leaking | Check `Flow.forkFlow` callers for missing wait |

## Raw output

Full hspec log at `/tmp/vayu-test.log`.

## Related

- `vayu-build` — run this first if a test file itself fails to compile.
- `vayu-planner` phase 5 — design-level testing guidance (properties, fixtures).
