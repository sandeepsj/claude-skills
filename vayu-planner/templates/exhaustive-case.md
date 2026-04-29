# Template — Exhaustive Case (and why wildcards are a trap)

## The pattern

```haskell
{-# OPTIONS_GHC -Wincomplete-patterns -Werror=incomplete-patterns #-}
module Core where

data OrderStatus
  = Pending
  | Paid
  | Shipped
  | Cancelled
  deriving stock (Eq, Show)

-- GOOD: every constructor listed
statusLabel :: OrderStatus -> Text
statusLabel = \case
  Pending   -> "Awaiting payment"
  Paid      -> "Payment received"
  Shipped   -> "On its way"
  Cancelled -> "Cancelled"
```

When someone adds `Refunded` to `OrderStatus`, the compiler will flag **every** `case` on `OrderStatus` in the codebase. That's the whole point of this language.

## The anti-pattern

```haskell
-- BAD: wildcard hides future enum additions
statusLabel :: OrderStatus -> Text
statusLabel s = case s of
  Pending -> "Awaiting payment"
  Paid    -> "Payment received"
  _       -> "Other"              -- silently swallows Refunded when added
```

When `Refunded` is added, this function keeps compiling, returns `"Other"` for refunds, and no one notices until a customer sees it.

## When wildcards are acceptable

Only when the wildcard's meaning genuinely covers all unlisted cases, *and that's by design, not laziness*. Examples:

```haskell
-- Defensible: "only interested in one case"
isPaid :: OrderStatus -> Bool
isPaid = \case
  Paid -> True
  _    -> False
```

Here the `_` cannot drift — if `isPaid` is ever wrong for a new constructor, the fix is obvious (add the new constructor as `False` or `True`). But even here, listing explicitly is safer:

```haskell
isPaid :: OrderStatus -> Bool
isPaid = \case
  Paid      -> True
  Pending   -> False
  Shipped   -> False
  Cancelled -> False
```

The second version flags on `Refunded` being added, forcing a conscious decision.

## Pragma sins

```haskell
-- NEVER do this in application code
{-# OPTIONS_GHC -fno-warn-incomplete-patterns #-}
{-# OPTIONS_GHC -fno-warn-incomplete-uni-patterns #-}
```

If you're tempted, you have a non-total function. Fix it.

## For records — avoid positional pattern matching

```haskell
-- BAD: breaks when fields are added/reordered
name (User n _ _) = n

-- GOOD: record syntax, compiler-checked
name User{userName} = userName
```

`OVERLAPPING` and `-fno-warn-name-shadowing` are similar smells: they silence the compiler instead of answering what it's telling you.
