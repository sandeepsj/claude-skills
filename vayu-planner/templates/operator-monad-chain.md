# Template — Operator-style Monadic Composition

## The rule of thumb

- **1–2 steps, data flows linearly** → operators.
- **3+ bindings reused** OR **nested case analysis** → `do`.

Do not write a 6-line `do` block where each binding is used exactly once.

## Translations

### Sequence with result

```haskell
-- do
do x <- readConfig
   parseConfig x

-- operator
readConfig >>= parseConfig
```

### Sequence, ignore intermediate

```haskell
do logInfo "starting"
   doWork
   logInfo "done"

-- operator
logInfo "starting" *> doWork <* logInfo "done"
```

`*>` discards the left, `<*` discards the right, so `doWork`'s result survives.

### Transform the result

```haskell
do x <- fetchUser uid
   pure (userName x)

-- operator
fetchUser uid <&> userName        -- <&> is fmap flipped, reads L-to-R
```

### Maybe chain

```haskell
do mUser <- findUser uid
   case mUser of
     Nothing -> pure Nothing
     Just u  -> do
       mProfile <- findProfile (userId u)
       pure mProfile

-- operator  (runMaybeT or >>=? helper)
runMaybeT $ do
  u       <- MaybeT (findUser uid)
  profile <- MaybeT (findProfile (userId u))
  pure profile

-- or with a >>=? helper (returns Nothing on Nothing, otherwise runs the next step)
findUser uid >>=? \u -> findProfile (userId u)
```

### Either / ExceptT chain

```haskell
do result <- runExceptT $ do
     u <- ExceptT (findUser uid)
     p <- ExceptT (findProfile (userId u))
     pure p

-- Kleisli compose (>=>) if both return the same `Either e`
findUser >=> findProfileFromUser
```

## When `do` wins

1. **Three or more bindings used more than once:**

   ```haskell
   do user    <- findUser uid
      orders  <- listOrders (userId user)
      profile <- findProfile (userId user)
      let total = sumTotals orders
      pure $ Report user profile orders total
   ```

   Inline with operators and it's unreadable.

2. **Nested case analysis driving branches:**

   ```haskell
   do user <- findUser uid
      case userPlan user of
        Free -> ...
        Paid -> do
          items <- listItems (userId user)
          case items of ...
   ```

3. **`let` bindings for pure computation interleaved with effects:**

   ```haskell
   do raw      <- readFile path
      let lines' = T.lines raw
      results   <- traverse process lines'
      pure (summarise results)
   ```

## Cheat sheet

| Op  | Name | Meaning |
|-----|------|---------|
| `>>=` | bind | `m a -> (a -> m b) -> m b` |
| `=<<` | reverse bind | `(a -> m b) -> m a -> m b` |
| `>>` / `*>` | sequence | discard left result |
| `<*` | sequence | discard right result |
| `<$>` | fmap infix | pure function lifted in |
| `<&>` | fmap flipped | data on left, function on right |
| `<*>` | apply | applicative composition |
| `>=>` | Kleisli compose | `(a -> m b) -> (b -> m c) -> (a -> m c)` |
| `<=<` | reverse Kleisli | math-order composition |

## Vayu helpers (from `Vayu.Utils.Maybe` and `Vayu.Utils.Either`)

Before writing a custom chain, check these — they cover the common cases idiomatically:

| Op | Type intuition | Use |
|----|----------------|-----|
| `>>=?` | `m (Maybe a) -> (a -> m (Maybe b)) -> m (Maybe b)` | Chain through `Nothing`; if the Maybe is `Nothing`, short-circuit and return `Nothing`; otherwise run the next step |
| `>>=??` | `m (Maybe (Either e a)) -> (a -> m (Maybe (Either e b))) -> m (Maybe (Either e b))` | Same but threads an `Either` through as well |
| `>.` | `m a -> (a -> b) -> m b` | Data on left, pure transform on right (variant of `<&>`) |
| `>$` | `m a -> b -> m b` | Run for effect, replace result |
| `?.` | `Maybe a -> (a -> b) -> Maybe b` | `<&>` specialised to `Maybe`, reads left-to-right |
| `??.` | `Maybe (Maybe a) -> (a -> b) -> Maybe (Maybe b)` | Transform inside nested Maybes |
| `>>=>` | `Flow (Either e a) -> (a -> Flow (Either e b)) -> Flow (Either e b)` | Kleisli compose over `Either`-in-`Flow`, short-circuits on `Left` |
| `>>=>>` | similar with an extra `Maybe` layer | Same idea, `Flow (Either e (Maybe a))` |

**Rule of thumb:** if your chain manipulates a `Flow (Maybe a)` or `Flow (Either e a)` and you find yourself writing a 5-line `do` with a `case`, check the Utils operator list first. The pattern probably has a single-operator spelling.

## Example — before and after

```haskell
-- Before — 7 lines of do + case for a 2-step chain
findActiveCustomer shopUrl cid = do
  mC <- CustomerSvc.findById shopUrl cid
  case mC of
    Nothing -> pure Nothing
    Just c  -> if isActive c
                 then pure (Just c)
                 else pure Nothing

-- After — operator style
findActiveCustomer shopUrl cid =
  CustomerSvc.findById shopUrl cid
    ?. (\c -> if isActive c then Just c else Nothing)
```
