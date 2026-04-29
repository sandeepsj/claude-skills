# Quick Reference — Functor / Applicative / Monad Operators

## Core operators

| Op | Name | Type | Plain English |
|----|------|------|---------------|
| `<$>` | fmap | `(a -> b) -> f a -> f b` | Apply a pure function inside a functor |
| `<&>` | fmap flipped | `f a -> (a -> b) -> f b` | Same, reads left-to-right |
| `$>` | replace-right | `f a -> b -> f b` | Keep effect, swap value |
| `<$` | replace-left | `a -> f b -> f a` | Swap value, keep effect |
| `<*>` | ap | `f (a -> b) -> f a -> f b` | Applicative apply |
| `*>` | seq-right | `f a -> f b -> f b` | Sequence, keep right |
| `<*` | seq-left | `f a -> f b -> f a` | Sequence, keep left |
| `>>=` | bind | `m a -> (a -> m b) -> m b` | Chain by result |
| `=<<` | reverse bind | `(a -> m b) -> m a -> m b` | Same, other direction |
| `>>` | seq | `m a -> m b -> m b` | Sequence, ignore left |
| `>=>` | Kleisli compose | `(a -> m b) -> (b -> m c) -> (a -> m c)` | Monadic function composition |
| `<=<` | reverse Kleisli | `(b -> m c) -> (a -> m b) -> (a -> m c)` | Reads math-style right-to-left |

## When to reach for each

- **`<$>`** — transforming a value inside a monad without needing its effect: `userName <$> fetchUser uid`
- **`<&>`** — same, when you want left-to-right reading: `fetchUser uid <&> userName`
- **`<*>`** — building a record from several effectful sources: `User <$> fetchName uid <*> fetchAge uid`
- **`>>=`** — when the next step *depends* on the previous result: `fetchUser uid >>= sendEmail`
- **`>=>`** — composing two functions that both return the same monad: `validate >=> persist`
- **`*>` / `<*`** — when you're sequencing for effect and only one side has a result you care about
- **`<$`** — cheap replace: `True <$ logInfo "done"`

## Traverse

| Function | Type | Use |
|----------|------|-----|
| `traverse` | `(a -> f b) -> t a -> f (t b)` | Apply an effectful function to each, collect |
| `traverse_` | `(a -> f b) -> t a -> f ()` | Same, discard results |
| `for` | flip of `traverse` | When the traversable is on the left |
| `for_` | flip of `traverse_` | Iteration for effect |
| `sequence` | `t (f a) -> f (t a)` | Invert the nesting |
| `mapM` | `= traverse` | Legacy synonym; prefer `traverse` |

## Alternative / MonadPlus

| Op | Name | Meaning |
|----|------|---------|
| `<\|>` | alt | "Try this, else that" (for `Maybe`, `Either String`, parsers) |
| `empty` | empty alt | Failure element |
| `guard` | assert | `guard p = if p then pure () else empty` |

## Common idioms

```haskell
-- Run an effect, discard result
_ <- doAction
-- or
void doAction

-- Collect N effects
replicateM 5 randomIO           -- returns [a]
replicateM_ 5 (putStrLn "hi")   -- returns ()

-- Map + filter in one pass
mapMaybe :: (a -> Maybe b) -> [a] -> [b]

-- Apply function if Just, else default
maybe defaultValue f mValue

-- Transform Either
either handleError handleSuccess eValue
```
