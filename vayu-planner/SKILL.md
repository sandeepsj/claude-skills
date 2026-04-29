---
name: vayu-planner
description: Plan or design Haskell changes in the Vayu repo — new endpoints, new DB tables, refactors, or any non-trivial work that touches src/Vayu. Walks the task through 8 phases (discover → model-domain → choose-effects → define-interfaces → implement → test → verify → review), enforcing layered architecture (Generated → Core → Product → Services), EulerHS Flow vs LogM effect choice, YAML-driven codegen, Pure Logging defaults, and the pre-commit checklist. Use when the user says "plan", "design", "add endpoint", "add table", "refactor", or asks how to approach a Vayu change.
allowed-tools: Read, Glob, Grep, Bash
---

# Vayu Planning Skill

Walk a Haskell task in Vayu through 8 phases. **Read each phase file on demand — do not paste all of them in one response.** The phases are designed to be consulted in order, but the user can jump to any one.

## Phases

1. [Discover](phases/00-discover.md) — restate the task, find the seam, read 2–3 neighbours, list constraints and unknowns.
2. [Model the domain](phases/01-model-domain.md) — ADTs, newtypes, smart constructors, make illegal states unrepresentable.
3. [Choose effects](phases/02-choose-effects.md) — **Flow vs. LogM decision tree**. Default to LogM for pure helpers.
4. [Define interfaces](phases/03-define-interfaces.md) — typeclasses, laws, signatures first.
5. [Implement](phases/04-implement.md) — Vayu layered architecture, logger wrappers, operator-style composition.
6. [Test](phases/05-test.md) — hspec, `runLogMPure` for LogM, CATS for contract tests.
7. [Verify](phases/06-verify.md) — `pnpm build`, regen, totality grep, pre-commit checklist.
8. [Review](phases/07-review.md) — structural + failure-mode pass before PR.

## Templates (load on demand)

**Generic Haskell patterns:**
- [newtype-smart-constructor](templates/newtype-smart-constructor.md) — safe wrappers for primitives with invariants.
- [tagless-final-service](templates/tagless-final-service.md) — swappable capabilities via typeclasses.
- [exhaustive-case](templates/exhaustive-case.md) — why wildcards on enums are a trap.
- [operator-monad-chain](templates/operator-monad-chain.md) — when to use `>>=` / `<&>` / `>=>` over `do`, including Vayu's `>>=?`, `>.`, `>$`.
- [quickcheck-property](templates/quickcheck-property.md) — property-test shape.

**Vayu-specific patterns:**
- [eulerhs-flow-action](templates/eulerhs-flow-action.md) — single-domain Flow action in Services/Internal.
- [servant-core-handler](templates/servant-core-handler.md) — route handler in Routes/Core.hs.
- [product-function](templates/product-function.md) — Product orchestration with logger wrappers.
- [pure-logm-helper](templates/pure-logm-helper.md) — **default shape** for pure helpers that need logs.

## Quick references

- [Golden rules](quick-reference/golden-rules.md) — banned partials, exhaustive cases, **all Vayu custom rules inline**.
- [Operators](quick-reference/operators.md) — `<$>`, `<&>`, `>>=`, `>=>`, and Vayu's `>>=?`, `>.`, `>$`, `??.`.
- [Monad transformers](quick-reference/monad-transformers.md) — mtl cheat sheet.
- [Safe list ops](quick-reference/safe-list-ops.md) — `listToMaybe`, `readMaybe`, `Vayu.Utils.Maybe.maybeHead`.

## Verification checklist

Run [verification.md](verification.md) before marking work complete.

## Companion skills

For operations that *do* things rather than plan them, use these sibling skills:

- **`vayu-codegen`** — walkthrough for adding a new endpoint / DB table / network call (YAML edits + regen + BreezeDB registration).
- **`vayu-build`** — run `pnpm build` and return a structured error list.
- **`vayu-test`** — run `npx dotenv -- bash -c '$STACK_PATH exec vayu-hspec'` and summarise failures.
- **`vayu-review`** — grep a diff for golden-rule violations.

## Codegen pipelines (always-on reminder)

| Command | Spec | Output |
|---------|------|--------|
| `pnpm run generate:api:backend` | `doc/Api.yaml` | `Types/Common/*`, `Types/Storage/*`, `API.hs`, `Accessor.hs` |
| `pnpm run generate:db:backend` | `doc/DBQueries.yaml` | `Queries/*.hs` |
| `pnpm run generate:network:backend` | `doc/NetworkCalls.yaml` | `NetworkCalls/*.hs` |

**Never edit files under `src/Vayu/Generated/`.** Change the YAML, then regenerate.

## How to use this skill

When a Vayu Haskell task arrives:

1. **Read `phases/00-discover.md`** and help the user produce a one-line restated task + seam + constraints. Do not skip this.
2. Advance through phases in order unless the user redirects. For each phase, read the phase file, then apply its guidance to the current task.
3. Pull in templates/quick-refs only when the phase calls for them (e.g. "see the `pure-logm-helper` template").
4. For phase 6 (verify) and phase 5 (test), hand off to the `vayu-build` / `vayu-test` skills rather than duplicating build/test execution here.
5. Before marking done, walk the user through `verification.md`.
