# Phase 02 — Choose Your Effects (Vayu edition)

**Goal:** decide *where* this code's side effects live — and in Vayu, that is a two-way choice between `FlowMonad.Flow` and `Vayu.Utils.LogM`.

## The only two options in Vayu

Vayu standardised on **EulerHS**, so there is no mtl-stack / polysemy / effectful / RIO question to answer. Every effectful function is in **`Flow`**. What's genuinely new and load-bearing is that Vayu *also* has **`LogM`** — a pure writer-over-DList monad — for helpers that need logs but no other effects.

**Default stance for new helpers:** write in `LogM`. Drop to `Flow` only when you genuinely need a Flow effect.

## The decision tree

Does this function need any of:

- a DB query (Generated queries, Storage/Queries)?
- an HTTP call (Services/External, network-call Generated)?
- a Redis / cache read or write?
- a config read (`Flow.getConfig`, feature-flag extractors via `Utils.Breeze`)?
- the clock (`getCurrentTime`, `getLocalTime`)?
- request context injected by the framework (shopUrl / requestId / sessionId beyond what's in args)?
- `throw` / `logAndThrowErr*` (genuine short-circuit of the request)?

- **Any one = yes** → `Flow`. Use `Vayu.Product.Logger.withProductAPILogging` (at the API boundary) or `withFunctionLogging` (for internal Flow helpers).
- **All no** → `LogM`. Use `Vayu.Utils.LogM.withFunctionCallLogging` and the mirrored primitives (`logInfo`, `logFailure`, `logFunctionCalled`, etc.).

## Why `LogM` is the default

Three concrete wins:

1. **Unit-testable without a Flow harness.** `runLogMPure :: LogM a -> (a, [LogEntry])` — plain hspec assertion on result + ordered log entries. No container stack, no DB, no mocks.
2. **Compiler-enforced purity.** `LogM` has no `MonadIO`, no `MonadTrans`, no `MonadFlow` instance. Attempting any Flow effect is a type error — you can't accidentally make a "pure" helper DB-bound two refactors from now.
3. **Same production behaviour.** `runLogM :: LogM a -> Flow a` replays every entry through `Logger.logEvent`, so request-context enrichment, async dispatch, and all transports apply identically to native Flow-side logging.

## Composition rules

- **Two `LogM` helpers compose via `>>=`.** Do *not* call `runLogM` in the middle of a `LogM` chain — only at the Flow boundary.
- **Take effectful data as parameters.** If your pure helper needs "now", take a `LocalTime` argument; let the Flow caller get it.
- **Return `Either e a` / `Maybe a` from `LogM` for failure.** The Flow caller decides how to throw.

## Error handling — four honest answers in Flow

When you *are* in Flow, the four error approaches available:

1. `Either DomainError a` — callers must deal; composes via `Utils.Either` helpers (`>>=>`, `>>=>>`).
2. `Maybe a` — only for "genuinely not found / absent" with no ambiguity.
3. `logAndThrowErr*` — for cases where the Flow should short-circuit to an HTTP error.
4. An effect raised through EulerHS's own primitives (rare, usually `throw`).

Do not invent a fifth — "return a silent default" is a bug farm.

## What to output

- "This function lives in **`LogM`** / **`Flow`**", with a one-line reason tied to the checklist above.
- If Flow: which logger wrapper wraps it (`withProductAPILogging` for API-bound, `withFunctionLogging` for internal).
- If LogM: where the Flow boundary is (the caller who does `runLogM`).
- The failure story in one sentence.

## Templates to pull in next

- Pure helper (default): `pure-logm-helper` template.
- Flow helper inside Product: `product-function` template.
- Flow helper in Services/Internal: `eulerhs-flow-action` template.

## Next phase

`define-interfaces` — signatures and typeclasses.
