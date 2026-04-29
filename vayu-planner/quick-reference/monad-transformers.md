# Quick Reference — Monad Transformers

## The stack

Transformers add one capability to an underlying monad. You stack them:

```haskell
newtype AppM a = AppM { runAppM :: ReaderT Env (ExceptT AppError IO) a }
  deriving (Functor, Applicative, Monad, MonadReader Env, MonadError AppError, MonadIO)
```

| Transformer | Adds | `lift` from |
|-------------|------|-------------|
| `ReaderT r` | read-only `r` via `ask`, `asks`, `local` | inner `m` |
| `StateT s`  | mutable `s` via `get`, `put`, `modify` | inner `m` |
| `WriterT w` | append-only log `w` via `tell` (avoid — see below) | inner `m` |
| `ExceptT e` | short-circuit with error `e` via `throwError`, `catchError` | inner `m` |
| `MaybeT`    | short-circuit on `Nothing` | inner `m` |
| `ContT r`   | explicit continuations (rare) | inner `m` |
| `LoggingT`  | `MonadLogger` — structured log output | inner `m` |

## `WriterT` warning

Strict `WriterT` is fine for small values. Lazy `WriterT` leaks space. If you want a log, either:
- Use a real logger (`MonadLogger`), or
- Use `StateT` with a `DList` accumulator

## Order matters

`StateT s (ExceptT e IO)` vs. `ExceptT e (StateT s IO)` give different semantics:
- Outer `StateT`: on error, state is **lost**
- Outer `ExceptT`: on error, state is **preserved**

Pick based on what the failure mode should be.

## MTL classes — the point

You rarely write code directly against a stack. You write against classes:

```haskell
-- Works with any monad that has Reader Env and MonadIO
greetUser
  :: (MonadReader Env m, MonadIO m)
  => UserId -> m ()
```

This means:
- Business logic doesn't know the stack order
- Tests can supply a different monad
- Adding a new layer doesn't require rewriting all call sites

## Lifting — less than you'd think

With `MonadTrans` and the MTL pattern, you rarely need to write `lift` manually. If you find yourself writing `lift . lift . lift`, the stack is too deep or the instance coverage is wrong.

## `MonadUnliftIO`

When you need to run `m`-actions inside an `IO`-bound API (like `bracket`, `finally`, `async`):

```haskell
withResource :: (MonadUnliftIO m) => (Handle -> m a) -> m a
withResource action = withRunInIO $ \run ->
  bracket openH closeH (\h -> run (action h))
```

`unliftio` is the pragmatic library here. Works for `ReaderT`-style stacks; doesn't work for `StateT` / `ExceptT` (because their state can't survive an IO callback).

## Escape hatches

- `runReaderT` / `runStateT` / `runExceptT` — peel the transformer off and get the inner action
- `evalStateT` / `execStateT` — keep result vs. keep state
- `runIdentityT` — no-op, used in type plumbing

## When to *not* use transformers

- If the whole app is `IO` + one `Reader`, prefer the bare `ReaderT Env IO` pattern (the "RIO" style)
- If you need algebraic effects with better composition, look at `effectful`, `polysemy`, or `cleff`
- If you only need IO, just use IO
