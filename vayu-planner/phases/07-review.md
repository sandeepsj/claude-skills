# Phase 07 — Review

**Goal:** read the diff as if a teammate wrote it. Catch what compilation and tests cannot.

## Structural checks

- **Single responsibility per module.** If a module gained unrelated functions, split before merging.
- **Imports are tidy.** Remove unused; group qualified vs. unqualified; no wildcard imports from project modules.
- **No dead code.** Unused helpers, commented-out blocks, `TODO` without an owner — delete.
- **No "just in case" abstractions.** A typeclass with one instance, a `Reader` wrapped around a single value, a parameterised function whose parameter is always the same — remove.

## Readability checks

- **Names match domain language.** If the product calls it "order", the code does too. Not "record", not "item".
- **Signatures tell a story.** A function with 5 `Maybe` parameters is a data-structure asking to exist.
- **Long functions have a reason.** More than ~30 lines, and you're probably hiding a sub-concept.
- **Comments explain WHY, not WHAT.** Delete every comment that restates the code in English.

## Failure-mode review

Walk each new effect-ful function and ask:
- What happens if the network call times out?
- What happens if this returns an empty list?
- What happens under concurrent writes?
- What happens if the caller retries this?
- What happens if the upstream changes its response shape?

You do not need to *handle* every case — you need to have *thought* about every case, and made a conscious decision for each.

## Idempotency and retries

For any mutation that could be retried:
- Is it safe to apply twice? (genuinely idempotent, or protected by a unique constraint / version check)
- If not, is the caller told it's not safe?

Idempotency failures surface as "duplicate orders" or "double-charged customers" in production. Catch them here.

## Security and PII

- No credentials, tokens, or PII in logs.
- No user input interpolated into SQL, shell, or HTML without escaping.
- Tokens redacted or hashed when crossing trust boundaries.

## Readability — the final test

Imagine the on-call engineer who's never seen this code, at 3am, with a pager alert. Can they:
- Find the relevant module from a stack trace?
- Understand the function's intent without reading callers?
- Form a hypothesis about the bug from the types alone?

If any answer is no, fix it now. That on-call engineer is probably you in six months.

## What to output

- A checklist you ran through, with any fixes made
- PR title and description, written last (not first) because by now you actually know what changed

## Done

`complete_planning` records the session and clears the planning state.
