# Phase 00 — Discover

**Goal:** before writing a line, understand the shape of the problem, the constraints the project imposes, and where in the codebase this work belongs.

## What to do

1. **Re-state the task in one sentence.** If you can't, you don't understand it yet — ask.
2. **Locate the seam.** Which module, layer, or boundary does the change live on? A new API endpoint, a new domain type, a bug fix in an effect? Naming the seam narrows the design.
3. **Read the neighbours.** Open 2–3 existing pieces of code that do something similar. Functional codebases reward imitation — most conventions are load-bearing.
4. **Enumerate constraints.** Legal, performance, backwards-compat, on-call. Each constraint eliminates options; unknown constraints cause rewrites.
5. **List the unknowns.** What do you not know yet that could invalidate the design? (Does this field exist? Is that call idempotent? What's the failure mode of the upstream?) Resolve the load-bearing ones now, not during implementation.

## Theory lens — type-driven design starts here

Before picking data types, you're picking *which states are possible*. In Haskell, your type system is the primary design tool — an hour spent here saves a day of `Maybe` shuffling later. Ask:

- What are the inputs? What *subset* of them is valid? (Anything you can't exclude with a type becomes a runtime check.)
- What are the outputs? Can they express "no result", "partial result", "failure with reason"?
- What's a *state* vs. an *event* vs. a *command* in this problem? Haskell distinguishes these cleanly; code that conflates them turns into spaghetti.

## What to output from this phase

A short design sketch, in plain prose:
- Task restated in one line
- Seam (module path + layer)
- 2–3 existing examples you'll imitate
- Constraints and open questions
- First guess at the top-level type(s) / function signatures

Do NOT start coding until the sketch exists. If the profile defines a codegen pipeline, the sketch must also say *which spec file(s)* will change, not just the generated output.

## Next phase

`model-domain` — turn the sketch into concrete types.
